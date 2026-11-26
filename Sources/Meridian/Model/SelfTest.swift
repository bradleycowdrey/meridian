import SwiftUI
import AppKit
import WidgetKit

/// Layout self-test, used by CI on a real Mac: `Meridian --selftest <dir>` opens the window,
/// steps through every size (with and without the city search open), records the window size
/// against the size the content needs, saves a PNG of each, writes report.txt, then quits.
/// It also writes larger renders for the Mac App Store screenshots (store-panel.png,
/// store-window.png, store-work-window.png, store-widget-*.png, store-work-widget-*.png), which
/// scripts/mac-store-shots.mjs composes.
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
        // The item may still count its panel as open (the check before only ordered it out), so a
        // first click can close it: click until it shows.
        var opened: NSWindow?
        for _ in 0..<3 where opened == nil {
            button.performClick(nil)
            try? await Task.sleep(for: .seconds(2))
            opened = NSApp.windows.first(where: { $0.isVisible && $0 !== desktop && $0 !== itemWindow && $0.frame.width > 300 })
        }
        guard let panel = opened, let view = panel.contentView else { return "\(file): panel did not open" }
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

    /// The cities of the "See who's at work" picture (scripts/mac-store-shots.mjs), with a city photo
    /// each, around the world: the picture takes four that are at work and one that isn't.
    private static let workPool: [(String, String)] = [
        ("Honolulu", "Pacific/Honolulu"), ("San Francisco", "America/Los_Angeles"), ("Denver", "America/Denver"),
        ("Chicago", "America/Chicago"), ("New York", "America/New_York"), ("Sao Paulo", "America/Sao_Paulo"),
        ("London", "Europe/London"), ("Paris", "Europe/Paris"), ("Berlin", "Europe/Berlin"), ("Cairo", "Africa/Cairo"),
        ("Nairobi", "Africa/Nairobi"), ("Dubai", "Asia/Dubai"), ("Mumbai", "Asia/Kolkata"), ("Bangkok", "Asia/Bangkok"),
        ("Singapore", "Asia/Singapore"), ("Hong Kong", "Asia/Hong_Kong"), ("Seoul", "Asia/Seoul"), ("Tokyo", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"), ("Auckland", "Pacific/Auckland"),
    ]
    /// Set by storeWorkWindow: those cities as the widget gets them, and which of them are working.
    private static var workSnapshot: WidgetSnapshot?
    private static var workingNames: Set<String> = []

    /// Writes store-work-window.png: the window showing five cities other than yours, four of them
    /// at work and one in its off hours, west to east, at the first moment from now (now, or a
    /// whole hour ahead) when four of them are working. Your cities are put back after.
    private static func storeWorkWindow(store: ZoneStore, content: NSView, dir: URL, travelHours: Int) async -> String {
        let yours = store.places
        let pool: [Place] = workPool.compactMap { name, zone in
            guard !yours.contains(where: { $0.name == name || $0.timeZoneID == zone }) else { return nil }
            if let entry = CityDirectory.all.first(where: { $0.name == name && $0.timeZoneID == zone }) {
                return Place(name: name, timeZoneID: zone, countryCode: entry.countryCode,
                             latitude: entry.latitude, longitude: entry.longitude)
            }
            return Place(name: name, timeZoneID: zone)
        }
        let anchor = TimeMath.hourAnchor(store.now)
        for hours in 0..<96 {
            let at = hours == 0 ? store.now : anchor.addingTimeInterval(Double(hours) * 3600)
            let offset = { (p: Place) in p.timeZone.secondsFromGMT(for: at) }
            // One city per UTC offset, at work; then four of them spread from west to east.
            var working: [Place] = []
            for p in pool.sorted(by: { offset($0) < offset($1) }) where store.isWorking(p, at: at)
                && !working.contains(where: { offset($0) == offset(p) }) { working.append(p) }
            guard working.count >= 4 else { continue }
            let four = (0..<4).map { working[Int((Double($0) * Double(working.count - 1) / 3).rounded())] }
            // And one in its off hours (not a weekend or holiday), as near the four as can be.
            let lo = offset(four.first!), hi = offset(four.last!)
            let off = pool.filter {
                WorkWeek.offLabel($0, at: at, start: store.workStart, end: store.workEnd) == "Off hours"
            }.min { a, b in
                let da = min(abs(offset(a) - lo), abs(offset(a) - hi)), db = min(abs(offset(b) - lo), abs(offset(b) - hi))
                return da < db
            }
            let cities = (four + (off.map { [$0] } ?? [])).sorted { offset($0) < offset($1) }
            store.places = cities
            store.offsetHours = hours
            try? await Task.sleep(for: .seconds(2))
            content.layoutSubtreeIfNeeded()
            var line = writeStorePNG(of: content, scale: 2, to: dir.appendingPathComponent("store-work-window.png"))
            // The hours ahead it shows (0: now, the menu bar's time), for scripts/mac-store-shots.mjs.
            try? "\(hours)\n".write(to: dir.appendingPathComponent("store-work.txt"), atomically: true, encoding: .utf8)
            workSnapshot = WidgetSnapshot.load()
            workingNames = Set(four.map(\.name))
            line += " (\(hours == 0 ? "now" : "+\(hours) h"); \(cities.map { "\($0.name)\(store.isWorking($0, at: at) ? "" : " off")" }.joined(separator: ", ")))"
            if hours != 0 && hours == travelHours { line += " (the same hour as store-window-travel.png)" }
            store.places = yours
            store.offsetHours = 0
            try? await Task.sleep(for: .seconds(1))
            return line
        }
        return "store-work-window.png: no hour in four days with four of its cities at work"
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
        // The store renders (window, panel, widgets) all show one minute, the menu bar's clock in the
        // screenshots: start them just after the minute turns (and the app's clock with it).
        for _ in 0..<70 {
            if Calendar.current.component(.second, from: Date()) <= 1,
               Calendar.current.component(.minute, from: store.now) == Calendar.current.component(.minute, from: Date()) { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        let storeMinute = store.now
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
            // "See who's at work": the same window with other cities, chosen so that most of them
            // are at work at the moment shown (store-work-window.png), and their widgets
            // (store-work-widget-*.png, below). The moment is now when four or more of these cities
            // are working now (so it is the menu bar's time), else the first whole hour ahead when
            // they are. Your cities are put back straight after.
            lines.append(await storeWorkWindow(store: store, content: content, dir: dir, travelHours: best))
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
        // More faces for the Mac App Store's widget picture (and the menu bar one): each of your
        // cities on its own small widget, your cities two by two on medium ones, and the cities of
        // "See who's at work" (a widget given its own cities) at every size.
        var faceSets: [(String, WidgetSnapshot, WidgetFamily, CGSize)] = []
        func part(_ base: WidgetSnapshot, _ cities: ArraySlice<WidgetSnapshot.City>) -> WidgetSnapshot {
            var copy = base; copy.cities = Array(cities); return copy
        }
        for i in snapshot.cities.indices {
            faceSets.append(("store-widget-small-\(i + 1).png", part(snapshot, snapshot.cities[i...i]), .systemSmall, faces[0].2))
        }
        if snapshot.cities.count > 2 {
            faceSets.append(("store-widget-medium-2.png", part(snapshot, snapshot.cities.dropFirst(2)), .systemMedium, faces[1].2))
        }
        if let work = workSnapshot {
            faceSets.append(("store-work-widget-large.png", work, .systemLarge, faces[2].2))
            let working = work.cities.filter { workingNames.contains($0.name) }
            for (i, pair) in stride(from: 0, to: working.count, by: 2).enumerated() {
                faceSets.append(("store-work-widget-medium-\(i + 1).png",
                                 part(work, working[pair..<min(pair + 2, working.count)]), .systemMedium, faces[1].2))
            }
            for (i, city) in working.enumerated() {
                faceSets.append(("store-work-widget-small-\(i + 1).png", part(work, [city][...]), .systemSmall, faces[0].2))
            }
        }
        for (file, face, family, size) in faceSets {
            let renderer = ImageRenderer(content: WidgetFacePreview(snapshot: face, date: store.now, family: family, size: size))
            renderer.scale = storeWidgetScale
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: dir.appendingPathComponent(file))) != nil {
                lines.append("\(file) \(rep.pixelsWide)x\(rep.pixelsHigh): \(face.cities.map(\.name).joined(separator: ", "))")
            } else {
                lines.append("\(file): not written")
            }
        }
        let sameMinute = Calendar.current.isDate(storeMinute, equalTo: store.now, toGranularity: .minute)
        lines.append("store renders: \(sameMinute ? "one minute throughout" : "the minute turned during them (store-clock.txt may not match)")")
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
