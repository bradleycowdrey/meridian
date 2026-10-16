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
    private static let interval: TimeInterval = 6 * 3600

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
        // Check on every launch, then every few hours while running.
        Task { if automatic { await check(userInitiated: false) } }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    private func checkIfDue() async {
        guard automatic else { return }
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
        phase = .downloading
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("MeridianUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let (downloaded, response) = try await URLSession.shared.download(from: release.dmg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
            let dmg = work.appendingPathComponent("Meridian.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            if let checksumURL = release.sha256 {
                let (checksum, _) = try await URLSession.shared.data(from: checksumURL)
                let expected = String(decoding: checksum, as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
                guard try Self.sha256(of: dmg) == expected else { throw UpdateError.checksum }
            }

            phase = .installing
            let staged = try await Self.extractApp(from: dmg, into: work)
            let stagedVersion = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard stagedVersion == release.version else { throw UpdateError.wrongVersion }

            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                // Can't replace in place (e.g. read-only location): hand the DMG to Finder instead.
                NSWorkspace.shared.open(dmg)
                phase = .available
                post("Finish in Finder: drag the new Meridian into Applications, replacing the old one.")
                return
            }
            try relaunch(replacing: target, with: staged, scratch: work)
        } catch {
            phase = .failed(error.localizedDescription)
            post("Update failed. \(error.localizedDescription)", error: true)
        }
    }

    /// Hands off to a shell helper that waits for us to quit, swaps the bundle (rolling back on
    /// failure), clears quarantine and relaunches.
    private func relaunch(replacing target: URL, with staged: URL, scratch: URL) throws {
        let script = scratch.appendingPathComponent("install.sh")
        try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.path]
        try process.run()
        NSApp.terminate(nil)
    }

    static let installScript = """
    #!/bin/sh
    # $1 = pid to wait for, $2 = installed app, $3 = staged new app
    PID="$1"; TARGET="$2"; NEW="$3"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
    rm -rf "$TARGET.old"
    if mv "$TARGET" "$TARGET.old"; then
      if /usr/bin/ditto "$NEW" "$TARGET"; then
        rm -rf "$TARGET.old"
      else
        rm -rf "$TARGET"; mv "$TARGET.old" "$TARGET"
      fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
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

    /// Numeric dotted comparison; anything after "-" (e.g. "-dev") is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-").first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
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
