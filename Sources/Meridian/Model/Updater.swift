import Foundation
import AppKit
import CryptoKit

/// Checks GitHub Releases for a newer Meridian and installs it in place.
///
/// Flow: fetch the latest release → compare versions → download the versioned DMG →
/// verify its SHA-256 against the published .sha256 → mount, copy the app out, unmount →
/// quit, swap the app bundle, relaunch (done by a tiny shell helper once we've exited).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading, installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let sha256: URL?
        let page: URL
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastChecked: Date?
    /// Short status shown inline in the panel (never a modal alert: a menu bar app's panel
    /// floats above normal windows, so alerts end up hidden behind it).
    @Published private(set) var notice: Notice?
    /// True while a check the user asked for is running, so the panel can show "Checking…".
    @Published private(set) var userChecking = false

    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "updates.automatic") } }

    let currentVersion: String
    private var timer: Timer?
    /// Automatic checks run once a day (manual checks any time).
    private static let interval: TimeInterval = 24 * 3600

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        automatic = UserDefaults.standard.object(forKey: "updates.automatic") as? Bool ?? true
        lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date
    }

    /// Only a real, installed .app can update itself (not `swift run`).
    var canSelfUpdate: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var isBusy: Bool { phase == .checking || phase == .downloading || phase == .installing }

    func start() {
        guard canSelfUpdate, timer == nil else { return }
        reportFailedInstall()
        // Once a day: at launch if the last check was over 24 hours ago, then whenever a day
        // has passed while running (checked every 30 minutes).
        Task { await checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    /// Checks if the last check is over a day old (also called whenever the panel opens).
    func checkIfDue() async {
        // Not in the CI self-test: the update banner would appear mid-test and move the controls.
        guard automatic, !SelfTest.isActive else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
        await check(userInitiated: false)
    }

    // MARK: Check

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        phase = .checking
        if userInitiated { userChecking = true; notice = nil }
        defer { userChecking = false }
        do {
            var request = URLRequest(url: Brand.releasesAPI, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Meridian/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.server }
            let release = try Self.parse(data)

            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")

            if Self.isNewer(release.version, than: currentVersion) {
                latest = release
                phase = .available
                // The panel's banner offers "Update"; nothing modal.
            } else {
                latest = nil
                phase = .upToDate
                if userInitiated { post("You’re up to date. Meridian \(currentVersion) is the newest version.") }
            }
        } catch {
            phase = .failed(error.localizedDescription)
            if userInitiated { post("Couldn’t check for updates. \(error.localizedDescription)", error: true) }
        }
    }

    // MARK: Install

    func install() async {
        guard let release = latest, !isBusy else { return }
        let target = Bundle.main.bundleURL
        // Running from the DMG, or from a read-only or translocated copy: it can't replace
        // itself, so send the user to the download before spending time on it.
        let inPlace = FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
            && !target.path.contains("/AppTranslocation/") && !target.path.hasPrefix("/Volumes/")
        guard inPlace else {
            NSWorkspace.shared.open(release.dmg)
            post("Meridian can’t update itself from here. The new version is downloading: open it and drag Meridian into Applications.", error: true)
            return
        }
        phase = .downloading
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeridianUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let (downloaded, response) = try await URLSession.shared.download(from: release.dmg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
            let dmg = work.appendingPathComponent("Meridian.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            // Every release publishes a checksum; never install without checking it.
            guard let checksumURL = release.sha256 else { throw UpdateError.checksum }
            let (checksum, checksumResponse) = try await URLSession.shared.data(from: checksumURL)
            guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.checksum }
            let expected = String(decoding: checksum, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            guard try Self.sha256(of: dmg) == expected else { throw UpdateError.checksum }

            phase = .installing
            let staged = try await Self.extractApp(from: dmg, into: work)
            let stagedVersion = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard stagedVersion == release.version else { throw UpdateError.wrongVersion }
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])

            try relaunch(replacing: target, with: staged, scratch: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            phase = .failed(error.localizedDescription)
            post("Update failed. \(error.localizedDescription)", error: true)
        }
    }

    /// Where the install helper leaves a note if it couldn't swap the app.
    private static var failureMarker: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Meridian/update-failed")
    }

    /// After a relaunch: say so if the last install didn't go through.
    private func reportFailedInstall() {
        guard let reason = try? String(contentsOf: Self.failureMarker, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: Self.failureMarker)
        post("The last update didn’t install (\(reason.trimmingCharacters(in: .whitespacesAndNewlines))). Your version is unchanged. Details are in ~/Library/Logs/Meridian-update.log.", error: true)
    }

    /// Hands off to a shell helper that waits for us to quit, swaps the bundle (rolling back on
    /// failure), clears quarantine and relaunches.
    private func relaunch(replacing target: URL, with staged: URL, scratch: URL) throws {
        let script = scratch.appendingPathComponent("install.sh")
        try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
        // Spawn in a new session: launchd kills an app's whole process group when it quits,
        // which would take a plain child process (and the update) down with it.
        try Self.spawnDetached("/bin/sh", [
            script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.path,
            Self.failureMarker.path, scratch.path,
        ])
        NSApp.terminate(nil)
        // Still here after the helper has given up waiting: quitting was cancelled.
        Task {
            try? await Task.sleep(for: .seconds(35))
            phase = .failed("Meridian didn’t quit")
            post("The update is ready but Meridian didn’t quit. Quit Meridian and open it again to finish.", error: true)
        }
    }

    static let installScript = """
    #!/bin/sh
    # $1 = pid to wait for, $2 = installed app, $3 = staged new app,
    # $4 = failure marker file, $5 = scratch folder to remove
    PID="$1"; TARGET="$2"; NEW="$3"; MARKER="$4"; SCRATCH="$5"
    mkdir -p "$HOME/Library/Logs"
    exec >>"$HOME/Library/Logs/Meridian-update.log" 2>&1
    echo "$(date) updating $TARGET from $NEW (waiting for pid $PID)"
    fail() { echo "$(date) failed: $1"; mkdir -p "$(dirname "$MARKER")"; echo "$1" > "$MARKER"; }
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
    if kill -0 "$PID" 2>/dev/null; then
      # Never swap the bundle under a running app; it shows its own message.
      echo "$(date) Meridian is still running; not installing"
      exit 1
    fi
    # Copy next to the app first, so the only moment without an app is two renames.
    rm -rf "$TARGET.new" "$TARGET.old"
    if ! /usr/bin/ditto "$NEW" "$TARGET.new"; then
      rm -rf "$TARGET.new"; fail "couldn’t copy the new version"
    elif ! mv "$TARGET" "$TARGET.old"; then
      rm -rf "$TARGET.new"; fail "couldn’t replace the app (permissions)"
    elif ! mv "$TARGET.new" "$TARGET"; then
      mv "$TARGET.old" "$TARGET"; rm -rf "$TARGET.new"; fail "couldn’t move the new version into place"
    else
      rm -rf "$TARGET.old" || echo "$(date) left $TARGET.old behind"
      /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    fi
    rm -rf "$SCRATCH"
    echo "$(date) relaunching"
    /usr/bin/open "$TARGET"
    """

    // MARK: Helpers

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    static func parse(_ data: Data) throws -> Release {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let versioned = release.assets.first { $0.name.hasPrefix("Meridian-") && $0.name.hasSuffix(".dmg") }
        guard let dmg = versioned ?? release.assets.first(where: { $0.name == "Meridian.dmg" }) else {
            throw UpdateError.noDownload
        }
        let checksum = release.assets.first { $0.name == dmg.name + ".sha256" }
        return Release(
            version: version,
            notes: release.body ?? "",
            dmg: dmg.browser_download_url,
            sha256: checksum?.browser_download_url,
            page: release.html_url
        )
    }

    /// Semantic-version comparison: "v"/"V" prefix and "+build" ignored, numeric parts
    /// compared in order, and a release beats its own pre-release ("1.0.0" > "1.0.0-beta").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parse(_ v: String) -> (numbers: [Int], pre: String?) {
            var text = v.trimmingCharacters(in: .whitespaces)
            if text.first == "v" || text.first == "V" { text.removeFirst() }
            text = text.split(separator: "+", maxSplits: 1).first.map(String.init) ?? text
            let pieces = text.split(separator: "-", maxSplits: 1).map(String.init)
            let numbers = (pieces.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (numbers, pieces.count > 1 ? pieces[1] : nil)
        }
        let a = parse(candidate), b = parse(current)
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x > y }
        }
        switch (a.pre, b.pre) {
        case (nil, .some): return true
        case (.some(let x), .some(let y)): return x.compare(y, options: .numeric) == .orderedDescending
        default: return false
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func extractApp(from dmg: URL, into work: URL) async throws -> URL {
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        let staged = work.appendingPathComponent("Meridian.app", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, "-quiet"])
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-force", "-quiet"]
            try? detach.run()
        }
        let source = mount.appendingPathComponent("Meridian.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateError.noApp }
        try await run("/usr/bin/ditto", [source.path, staged.path])
        return staged
    }

    /// posix_spawn with POSIX_SPAWN_SETSID (0x0400): the child gets its own session and process
    /// group, so it keeps running after Meridian exits.
    private static func spawnDetached(_ tool: String, _ arguments: [String]) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // SETSID, plus CLOEXEC_DEFAULT (0x4000) so the helper inherits none of our open files.
        posix_spawnattr_setflags(&attributes, Int16(0x0400 | 0x4000))
        let argv: [UnsafeMutablePointer<CChar>?] = ([tool] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, tool, nil, &attributes, argv, environ)
        guard status == 0 else { throw UpdateError.tool("posix_spawn", status) }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.tool((tool as NSString).lastPathComponent, finished.terminationStatus))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Shows a message in the panel. Confirmations fade after a few seconds; errors stay until dismissed.
    private func post(_ text: String, error: Bool = false) {
        let notice = Notice(text: text, isError: error)
        self.notice = notice
        guard !error else { return }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if self.notice == notice { self.notice = nil }
        }
    }

    func dismissNotice() { notice = nil }

    /// Opens the release page in the browser as a manual fallback.
    func openReleasePage() {
        NSWorkspace.shared.open(latest?.page ?? Brand.repository.appendingPathComponent("releases/latest"))
    }
}

enum UpdateError: LocalizedError {
    case server, download, checksum, noDownload, noApp, wrongVersion
    case tool(String, Int32)

    var errorDescription: String? {
        switch self {
        case .server: return "GitHub didn’t respond. Check your internet connection and try again."
        case .download: return "The download didn’t finish."
        case .checksum: return "The download didn’t match its published checksum, so it wasn’t installed."
        case .noDownload: return "The latest release has no Mac download yet."
        case .noApp: return "The download didn’t contain Meridian.app."
        case .wrongVersion: return "The downloaded app isn’t the expected version."
        case .tool(let name, let status): return "\(name) failed (exit \(status))."
        }
    }
}
