import Foundation
import WidgetKit

/// Keeps macOS pointed at this copy of Meridian and its widget.
///
/// macOS can drop a widget from the Edit Widgets gallery when it knows about several copies of
/// the app (a mounted DMG, one in Downloads, the bundle an update replaced). So each time
/// Meridian opens from Applications, it unregisters other copies, re-registers itself and its
/// widget extension, and asks the widgets to redraw. The widget service (chronod) also keeps its
/// own record of each widget and can hold on to an older version's after an update, so the first
/// time a new version opens, and on Settings → Refresh Widgets, Meridian restarts it (macOS
/// relaunches it straight away). It runs in the background and is silent; details go to
/// ~/Library/Logs/Meridian-widget.log.
enum WidgetRegistration {
    static let bundleID = "me.bradcowdrey.comridian"
    static let widgetID = "me.bradcowdrey.comridian.widget"
    private static let restartedKey = "widgetServiceRestartedForBuild"
    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// True when running as an installed app (not `swift run`, not a copy in Downloads or a DMG).
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.path
        return Bundle.main.bundleURL.pathExtension == "app"
            && (path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/"))
    }

    /// - Parameter restartService: restart the widget service even if this version already did.
    static func refresh(restartService: Bool = false, completion: (@MainActor () -> Void)? = nil) {
        guard isInstalled, !SelfTest.isActive else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let defaults = UserDefaults.standard
        let restart = restartService || defaults.string(forKey: restartedKey) != build
        let app = Bundle.main.bundleURL.path
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/MeridianWidget.appex").path
        DispatchQueue.global(qos: .utility).async {
            var log = ["\(Date()) refreshing widget registration for \(app)"]
            for other in otherRegisteredCopies(excluding: app) {
                log.append("unregister \(other): \(run(lsregister, ["-u", other]))")
            }
            log.append("register app: \(run(lsregister, ["-f", app]))")
            log.append("register widget: \(run("/usr/bin/pluginkit", ["-a", appex]))")
            log.append("enable widget: \(run("/usr/bin/pluginkit", ["-e", "use", "-i", widgetID]))")
            if restart {
                log.append("restart widget service: \(run("/usr/bin/killall", ["chronod"]))")
                Thread.sleep(forTimeInterval: 2)  // give launchd a moment to bring it back
                defaults.set(build, forKey: restartedKey)
            }
            write(log)
            Task { @MainActor in
                WidgetCenter.shared.reloadAllTimelines()
                completion?()
            }
        }
    }

    /// Paths of other Meridian.app bundles LaunchServices knows about.
    private static func otherRegisteredCopies(excluding current: String) -> [String] {
        let dump = output(lsregister, ["-dump", "Bundle"])
        var paths: Set<String> = []
        // Records are separated by lines of dashes; each has "path:" and "identifier:" fields.
        var records: [[String]] = [[]]
        for raw in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.count >= 10 && line.allSatisfy({ $0 == "-" }) { records.append([]) } else { records[records.count - 1].append(line) }
        }
        for lines in records {
            guard lines.contains(where: { $0.hasPrefix("identifier:") && field($0) == bundleID }),
                  let pathLine = lines.first(where: { $0.hasPrefix("path:") })
            else { continue }
            // "path: /Applications/Meridian.app (0x1234)"
            var path = field(pathLine)
            if let range = path.range(of: " (0x", options: .backwards) { path = String(path[..<range.lowerBound]) }
            if path.hasSuffix(".app"), path != current { paths.insert(path) }
        }
        return paths.sorted()
    }

    private static func field(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func output(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func write(_ lines: [String]) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Meridian-widget.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
