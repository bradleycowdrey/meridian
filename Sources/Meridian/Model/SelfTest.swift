import SwiftUI
import AppKit
import WidgetKit

/// Layout self-test, used by CI on a real Mac: `Meridian --selftest <dir>` opens the window,
/// steps through every size (with and without the city search open), records the window size
/// against the size the content needs, saves a PNG of each, writes report.txt, then quits.
/// It also writes larger renders for the Mac App Store screenshots (store-panel.png,
/// store-window.png, store-widget-*.png), which scripts/mac-store-shots.mjs composes.
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
    private static func menuBarPanelCheck(dir: URL, desktop: NSWindow?) async -> String {
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        guard let itemWindow = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("StatusBarWindow") }),
              let content = itemWindow.contentView, let button = buttons(in: content).first ?? (content.superview.flatMap { buttons(in: $0).first })
        else { return "menu bar panel: no menu bar item found" }
        let item = itemWindow.frame
        button.performClick(nil)
        try? await Task.sleep(for: .seconds(2))
        guard let panel = NSApp.windows.first(where: {
            $0.isVisible && $0 !== desktop && $0 !== itemWindow && $0.frame.width > 300
        }) else { return "menu bar panel: did not open (item \(item))" }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let w = panel.frame.width
        let expected = min(max((item.midX - w / 2).rounded(), visible.minX), max(visible.minX, visible.maxX - w))
        let ok = abs(panel.frame.minX - expected) <= 1
        var storeShot = "store-panel.png: no view"
        if let view = panel.contentView {
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("menubar-panel.png"))
            }
            // The same panel at 2x, for the Mac App Store screenshots (scripts/mac-store-shots.mjs).
            storeShot = writeStorePNG(of: view, scale: 2, to: dir.appendingPathComponent("store-panel.png"))
        }
        panel.orderOut(nil)
        return "menu bar panel: item centre x \(Int(item.midX)), panel x \(Int(panel.frame.minX))..\(Int(panel.frame.maxX)) centre \(Int(panel.frame.midX)),"
            + " expected x \(Int(expected)) (screen \(Int(visible.minX))..\(Int(visible.maxX))) \(ok ? "OK" : "WRONG"); \(storeShot)"
    }

    /// Opens the menu bar panel, writes it at 2x to `file` (for the Mac App Store screenshots) and
    /// closes it. Returns a line for report.txt.
    private static func storePanel(dir: URL, desktop: NSWindow?, file: String) async -> String {
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        guard let itemWindow = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("StatusBarWindow") }),
              let content = itemWindow.contentView, let button = buttons(in: content).first ?? (content.superview.flatMap { buttons(in: $0).first })
        else { return "\(file): no menu bar item found" }
        button.performClick(nil)
        try? await Task.sleep(for: .seconds(2))
        guard let panel = NSApp.windows.first(where: {
            $0.isVisible && $0 !== desktop && $0 !== itemWindow && $0.frame.width > 300
        }), let view = panel.contentView else { return "\(file): panel did not open" }
        view.layoutSubtreeIfNeeded()
        let line = writeStorePNG(of: view, scale: 2, to: dir.appendingPathComponent(file))
        panel.orderOut(nil)
        return line
    }

    /// Scale of the widget renders made for the App Store screenshots: above the 2x of a Retina
    /// desktop, so scripts/mac-store-shots.mjs can place them at their point size and still downsample.
    private static let storeWidgetScale: CGFloat = 3

    /// Draws `view` into a bitmap at `scale` pixels per point, whatever the scale of the display
    /// it's on (CI's virtual display is 1x), and writes it as a PNG. For the Mac App Store
    /// screenshots, which are 2880x1800. Returns a line for report.txt.
    private static func writeStorePNG(of view: NSView, scale: CGFloat, to url: URL) -> String {
        let bounds = view.bounds
        let width = Int((bounds.width * scale).rounded()), height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return "\(url.lastPathComponent): no bitmap" }
        rep.size = bounds.size   // points: drawing is scaled up to the pixel size
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil
        else { return "\(url.lastPathComponent): not written" }
        return "\(url.lastPathComponent) \(width)x\(height)"
    }

    /// Whether the bitmap's top row of pixels is free of red: every sample dark in red and with
    /// red close to blue (the old 3 pt crimson band was red 0.6, blue 0.24).
    private static func topRowIsNotRed(_ rep: NSBitmapImageRep?) -> (ok: Bool, detail: String) {
        guard let rep, rep.pixelsWide > 10, rep.pixelsHigh > 2 else { return (false, "no bitmap") }
        var worst = ""
        var sampled = 0
        for step in 1...9 {
            let x = rep.pixelsWide * step / 10
            guard let raw = rep.colorAt(x: x, y: 1),
                  let color = raw.usingColorSpace(.sRGB) ?? raw.usingColorSpace(.deviceRGB) else { continue }
            sampled += 1
            let red = color.redComponent, blue = color.blueComponent
            if !(red < 0.25 && abs(red - blue) < 0.1) && worst.isEmpty {
                worst = String(format: "x %d: red %.2f blue %.2f", x, Double(red), Double(blue))
            }
        }
        guard sampled > 0 else { return (false, "no pixels read") }
        return (worst.isEmpty, worst)
    }

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
        // The Medium panel as drawn (search closed), for the look check below.
        var mediumBase: NSBitmapImageRep?

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
                    if !addingState && size == .medium { mediumBase = rep }
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
        // The look: the panel's top edge is the near-black surface, with no crimson band across it.
        let band = topRowIsNotRed(mediumBase)
        functional.record("panel: no crimson band", band.ok, band.detail)
        let results = await functional.run()
        try? results.joined(separator: "\n").write(to: dir.appendingPathComponent("functional.txt"), atomically: true, encoding: .utf8)
        lines.append(results[0])

        // The desktop window at Large, at 2x, for the Mac App Store screenshots: after the
        // functional test, so it shows the same cities as the menu bar panel. The size is put
        // back before the panel check, so menubar-panel.png is unchanged.
        adding.wrappedValue = false
        editing.wrappedValue = false
        let sizeBefore = store.uiSize
        store.uiSize = .large
        try? await Task.sleep(for: .seconds(1.5))
        if let content = host.window?.contentView {
            content.layoutSubtreeIfNeeded()
            lines.append(writeStorePNG(of: content, scale: 2, to: dir.appendingPathComponent("store-window.png")))
            // The time the window shows, as the Mac menu bar writes it ("Wed Nov 25  8:36 PM"), so
            // the screenshots' menu bar shows the same time as the app.
            let clock = DateFormatter()
            clock.locale = Locale(identifier: "en_US_POSIX")
            clock.dateFormat = "EEE MMM d'  'h:mm a"
            try? (clock.string(from: store.now) + "\n").write(to: dir.appendingPathComponent("store-clock.txt"), atomically: true, encoding: .utf8)
            // The same window after dragging the hours along: travelled to the hour, 2 to 23 hours
            // ahead, when the most of your cities are in their working hours (the first such hour).
            let anchor = TimeMath.hourAnchor(store.now)
            var best = 2, bestCount = -1
            for hours in 2...23 {
                let at = anchor.addingTimeInterval(Double(hours) * 3600)
                let count = store.places.filter { store.isWorking($0, at: at) }.count
                if count > bestCount { best = hours; bestCount = count }
            }
            store.offsetHours = best
            try? await Task.sleep(for: .seconds(2))
            content.layoutSubtreeIfNeeded()
            lines.append(writeStorePNG(of: content, scale: 2, to: dir.appendingPathComponent("store-window-travel.png"))
                         + " (+\(best) h, \(bestCount) of \(store.places.count) cities working)")
            store.offsetHours = 0
            try? await Task.sleep(for: .seconds(1))
        } else {
            lines.append("store-window.png: no window")
        }
        store.uiSize = sizeBefore
        try? await Task.sleep(for: .seconds(1.5))

        // Menu bar panel: click Meridian's menu bar item; the panel should open centred under it
        // (moved sideways only as far as needed to stay on screen).
        lines.append(await menuBarPanelCheck(dir: dir, desktop: host.window))
        // The panel again at Large, at 2x, for the Mac App Store screenshots (store-panel-large.png).
        store.uiSize = .large
        try? await Task.sleep(for: .seconds(1.5))
        lines.append(await storePanel(dir: dir, desktop: host.window, file: "store-panel-large.png"))
        store.uiSize = sizeBefore
        try? await Task.sleep(for: .seconds(1.5))

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
            let face = WidgetFacePreview(snapshot: name.hasSuffix("stress") ? stress : snapshot, date: store.now,
                                         family: family, size: size)
            let renderer = ImageRenderer(content: face)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("widget-\(name).png"))
            }
        }
        // The same faces (your cities) larger, for the Mac App Store screenshots.
        for (name, family, size) in faces {
            let renderer = ImageRenderer(content: WidgetFacePreview(snapshot: snapshot, date: store.now,
                                                                    family: family, size: size))
            renderer.scale = storeWidgetScale
            let file = "store-widget-\(name).png"
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: dir.appendingPathComponent(file))) != nil {
                lines.append("\(file) \(rep.pixelsWide)x\(rep.pixelsHigh)")
            } else {
                lines.append("\(file): not written")
            }
        }
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
