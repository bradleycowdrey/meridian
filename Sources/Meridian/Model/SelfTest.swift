import SwiftUI
import AppKit

/// Layout self-test, used by CI on a real Mac: `Meridian --selftest <dir>` opens the window,
/// steps through every size (with and without the city search open), records the window size
/// against the size the content needs, saves a PNG of each, writes report.txt, then quits.
/// Inert unless that launch argument is present.
@MainActor
enum SelfTest {
    static let outputDir: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()

    static var isActive: Bool { outputDir != nil }
    private static var started = false

    static func run(store: ZoneStore, adding: Binding<Bool>, host: HostWindow) async {
        guard let dir = outputDir, !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var lines = ["screen visible frame \(Int(screen.minX)),\(Int(screen.minY)) \(Int(screen.width))x\(Int(screen.height))"]

        for addingState in [false, true] {
            adding.wrappedValue = addingState
            for size in UISize.allCases {
                store.uiSize = size
                try? await Task.sleep(for: .seconds(1.5))
                guard let window = host.window, let content = window.contentView else {
                    lines.append("\(size.rawValue) adding=\(addingState): no window")
                    continue
                }
                content.layoutSubtreeIfNeeded()
                let fit = content.fittingSize
                let frame = window.frame
                let bounds = content.bounds
                let clipped = fit.width > bounds.width + 1 || fit.height > bounds.height + 1
                let onScreen = screen.isEmpty || screen.insetBy(dx: -1, dy: -1).contains(frame)
                lines.append(
                    "\(size.rawValue) adding=\(addingState) window \(Int(frame.width))x\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))"
                    + " content \(Int(bounds.width))x\(Int(bounds.height)) needs \(Int(fit.width))x\(Int(fit.height))"
                    + " \(clipped ? "CLIPPED" : "fits") \(onScreen ? "onscreen" : "OFFSCREEN")"
                )
                if let rep = content.bitmapImageRepForCachingDisplay(in: bounds) {
                    content.cacheDisplay(in: bounds, to: rep)
                    let name = "\(addingState ? "add" : "base")-\(UISize.allCases.firstIndex(of: size)!)-\(size.rawValue).png"
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                }
            }
        }
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
