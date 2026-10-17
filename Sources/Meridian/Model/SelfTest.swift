import SwiftUI
import AppKit
import WidgetKit

/// Layout self-test, used by CI on a real Mac: `Meridian --selftest <dir>` opens the window,
/// steps through every size (with and without the city search open), records the window size
/// against the size the content needs, saves a PNG of each, writes report.txt, then quits.
/// Inert unless that launch argument is present.
@MainActor
enum SelfTest {
    nonisolated static let outputDir: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()

    nonisolated static var isActive: Bool { outputDir != nil }

    /// Diagnostic line on stderr (captured by CI as app.log); silent outside the self-test.
    nonisolated static func log(_ message: @autoclosure () -> String) {
        guard isActive else { return }
        FileHandle.standardError.write(Data(("[selftest] " + message() + "\n").utf8))
    }
    private static var started = false

    static func run(store: ZoneStore, adding: Binding<Bool>, editing: Binding<Bool>, host: HostWindow) async {
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
        // Window Position: each request should land flush with that edge (16pt margin), top-aligned.
        adding.wrappedValue = false
        store.uiSize = .medium
        try? await Task.sleep(for: .seconds(1.5))
        for placement in WindowPlacement.allCases {
            WindowPlacement.request(.edge(placement))
            try? await Task.sleep(for: .seconds(1.2))
            guard let window = host.window else { continue }
            let f = window.frame
            let expectedX: CGFloat
            switch placement {
            case .left: expectedX = screen.minX + 16
            case .center: expectedX = (screen.midX - f.width / 2).rounded()
            case .right: expectedX = screen.maxX - f.width - 16
            }
            let ok = abs(f.minX - expectedX) <= 1 && abs(f.maxY - (screen.maxY - 16)) <= 1
            lines.append("position \(placement.rawValue): window x \(Int(f.minX))..\(Int(f.maxX)) top \(Int(f.maxY)) expected x \(Int(expectedX)) top \(Int(screen.maxY - 16)) \(ok ? "OK" : "WRONG")")
        }
        // Every function, at every size and in both fonts.
        let functional = FunctionalTest(store: store, adding: adding, editing: editing, host: host)
        let results = await functional.run()
        try? results.joined(separator: "\n").write(to: dir.appendingPathComponent("functional.txt"), atomically: true, encoding: .utf8)
        lines.append(results[0])

        // Desktop widget faces, at the macOS widget sizes, from the file the app just wrote.
        let faces: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("large", .systemLarge, CGSize(width: 364, height: 376)),
        ]
        let snapshot = WidgetSnapshot.load()
        lines.append("widget file \(FileManager.default.fileExists(atPath: WidgetSnapshot.fileURL.path) ? "written" : "MISSING"), \(snapshot.cities.count) cities")
        // Worst case too: seven cities, long names, half-hour zones, 12-hour time.
        let stress = WidgetSnapshot(cities: [
            .init(name: "San Francisco", timeZoneID: "America/Los_Angeles"),
            .init(name: "St. John's", timeZoneID: "America/St_Johns"),
            .init(name: "Rio de Janeiro", timeZoneID: "America/Sao_Paulo"),
            .init(name: "London", timeZoneID: "Europe/London"),
            .init(name: "Kolkata", timeZoneID: "Asia/Kolkata"),
            .init(name: "Kathmandu", timeZoneID: "Asia/Kathmandu"),
            .init(name: "Adelaide", timeZoneID: "Australia/Adelaide"),
        ], use24h: false)
        for (name, family, size) in faces + faces.map({ ("\($0.0)-stress", $0.1, $0.2) }) {
            let face = WidgetClockView(snapshot: name.hasSuffix("stress") ? stress : snapshot, date: store.now, family: family)
                .frame(width: size.width, height: size.height)
                .background(WidgetTone.bg)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            let renderer = ImageRenderer(content: face)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("widget-\(name).png"))
            }
        }
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
