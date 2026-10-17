import SwiftUI
import AppKit

/// Functional checks run by the CI self-test on a real Mac (`Meridian --selftest <dir>`).
/// The logic checks call the model directly; the interface checks find real controls by the
/// frames they report (see `testID`) and click them with synthesized mouse events, at every size and in
/// both fonts, so hit-testing problems (like the delete button that stopped responding) show up.
@MainActor
final class FunctionalTest {
    let store: ZoneStore
    let adding: Binding<Bool>
    let editing: Binding<Bool>
    let host: HostWindow
    private(set) var lines: [String] = []
    private(set) var passed = 0
    private(set) var failed = 0

    init(store: ZoneStore, adding: Binding<Bool>, editing: Binding<Bool>, host: HostWindow) {
        self.store = store
        self.adding = adding
        self.editing = editing
        self.host = host
    }

    private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1 } else { failed += 1 }
        let extra = detail()
        lines.append("\(ok ? "PASS" : "FAIL") \(name)\(extra.isEmpty ? "" : " (\(extra))")")
    }

    private func settle(_ seconds: Double = 0.6) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    nonisolated private static let baseline: [(String, String)] = [
        ("Paris", "Europe/Paris"), ("New York", "America/New_York"),
        ("Kolkata", "Asia/Kolkata"), ("Tokyo", "Asia/Tokyo"),
    ]

    private func reset(_ cities: [(String, String)] = baseline) {
        store.places = cities.map { Place(name: $0.0, timeZoneID: $0.1) }
        store.offsetHours = 0
        adding.wrappedValue = false
        editing.wrappedValue = false
    }

    func run() async -> [String] {
        logic()
        await interface()
        lines.insert("functional: \(passed) passed, \(failed) failed", at: 0)
        return lines
    }

    // MARK: Logic

    private func logic() {
        // Search
        func top(_ q: String) -> CityEntry? { CityDirectory.search(q).first }
        check("search 'LHR' finds London", top("LHR")?.name == "London", top("LHR")?.name ?? "nil")
        check("search 'sfo' finds San Francisco", top("sfo")?.name == "San Francisco", top("sfo")?.name ?? "nil")
        check("search 'lon' starts with London", top("lon")?.name == "London", top("lon")?.name ?? "nil")
        check("search 'PST' gives a Pacific zone", top("PST").map { TimeZone(identifier: $0.timeZoneID)?.identifier.contains("Los_Angeles") ?? false } ?? false,
              top("PST")?.timeZoneID ?? "nil")
        for (q, seconds) in [("UTC+5:30", 19_800), ("gmt-3", -10_800), ("+9", 32_400), ("UTC−4", -14_400)] {
            let entry = top(q)
            let zone = entry.flatMap { TimeZone(identifier: $0.timeZoneID) }
            check("search '\(q)' is a fixed \(seconds)s zone that round-trips", zone?.secondsFromGMT() == seconds,
                  "\(entry?.timeZoneID ?? "nil") -> \(zone?.secondsFromGMT().description ?? "nil")")
        }
        check("search 'GMT+5' has one offset row", CityDirectory.search("GMT+5").filter { $0.region.hasPrefix("Fixed") || $0.name == "GMT+5" }.count == 1,
              CityDirectory.search("GMT+5").prefix(3).map(\.name).joined(separator: ","))
        check("search 'UTC+5:75' is not an offset", CityDirectory.search("UTC+5:75").allSatisfy { !$0.region.hasPrefix("Fixed") })
        check("search '' is empty", CityDirectory.search("  ").isEmpty)
        check("search gibberish is empty", CityDirectory.search("zzqxj").isEmpty)
        check("search 'kathmandu' is +5:45", top("kathmandu").flatMap { TimeZone(identifier: $0.timeZoneID)?.secondsFromGMT() } == 20_700)

        // Offsets and days
        check("offset +5:30", TimeMath.offsetLabel(seconds: 19_800) == "UTC+5:30")
        check("offset −3:30", TimeMath.offsetLabel(seconds: -12_600) == "UTC−3:30")
        check("offset 0", TimeMath.offsetLabel(seconds: 0) == "UTC")
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        let lateUTC = Date(timeIntervalSince1970: 1_792_193_400)   // 2026-10-16 23:30 UTC
        let earlyUTC = Date(timeIntervalSince1970: 1_792_116_000)  // 2026-10-16 02:00 UTC
        check("day shift +1 (Kiritimati, late UTC)", TimeMath.dayShift(lateUTC, zone: TimeZone(identifier: "Pacific/Kiritimati")!) == 1)
        check("day shift −1 (Honolulu, early UTC)", TimeMath.dayShift(earlyUTC, zone: TimeZone(identifier: "Pacific/Honolulu")!) == -1)
        check("day shift 0 (London)", TimeMath.dayShift(earlyUTC, zone: TimeZone(identifier: "Europe/London")!) == 0)
        check("12h time", TimeMath.time(earlyUTC, in: TimeZone(identifier: "UTC")!, use24h: false) == "2:00 AM")
        check("24h time", TimeMath.time(earlyUTC, in: TimeZone(identifier: "Asia/Kolkata")!, use24h: true) == "07:30")
        NSTimeZone.default = saved

        // Store
        reset()
        let count = store.places.count
        let berlin = CityEntry(name: "Berlin", region: "Europe", timeZoneID: "Europe/Berlin")
        store.add(berlin)
        check("add appends", store.places.count == count + 1 && store.places.last?.name == "Berlin")
        store.add(berlin)
        check("adding the same city twice is ignored", store.places.count == count + 1)
        store.move(from: IndexSet(integer: store.places.count - 1), to: 0)
        check("move to top", store.places.first?.name == "Berlin")
        store.menuBarPlaceID = store.places.first?.id
        store.remove(store.places[0])
        check("remove clears the menu bar city", store.menuBarPlaceID == nil && store.menuBarPlace?.name == "Paris")
        for i in 0..<20 { store.add(CityEntry(name: "City \(i)", region: "", timeZoneID: "UTC")) }
        check("max \(ZoneStore.maxPlaces) cities", store.places.count == ZoneStore.maxPlaces && !store.canAdd, "\(store.places.count)")
        reset()

        store.offsetHours = 0
        store.travel(3)
        let expected = TimeMath.hourAnchor(store.now).addingTimeInterval(3 * 3600)
        check("travel +3 selects the hour", store.offsetHours == 3 && store.selectedMoment() == expected)
        store.backToNow()
        check("Now returns", store.offsetHours == 0 && store.selectedMoment() == store.now)

        let (ws, we) = (store.workStart, store.workEnd)
        store.workStart = 22; store.workEnd = 6
        check("overnight work hours", store.isWorkHour(23) && store.isWorkHour(3) && !store.isWorkHour(12))
        store.workStart = 9; store.workEnd = 24
        check("work hours ending at 24", store.isWorkHour(23) && !store.isWorkHour(8))
        store.workStart = 9; store.workEnd = 9
        check("equal work start and end means all day", store.isWorkHour(3) && store.isWorkHour(15))
        store.workStart = ws; store.workEnd = we

        let keep = store.places
        store.places = []
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("keep", forType: .string)
        store.copyMoment()
        check("copy with no cities leaves the clipboard alone", NSPasteboard.general.string(forType: .string) == "keep")
        store.places = keep
        store.copyMoment()
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        check("copy moment lists every city", copied.split(separator: "\n").count == store.places.count && copied.contains("Kolkata"),
              copied.replacingOccurrences(of: "\n", with: " | "))

        // Widget hand-off
        store.add(CityEntry(name: "Lisbon", region: "Europe", timeZoneID: "Europe/Lisbon"))
        check("widget file follows cities", WidgetSnapshot.load().cities.last?.name == "Lisbon")
        let h24 = store.use24h
        store.use24h.toggle()
        check("widget file follows 12/24h", WidgetSnapshot.load().use24h == store.use24h)
        store.use24h = h24

        // Updates
        check("version 0.10.0 > 0.9.9", Updater.isNewer("0.10.0", than: "0.9.9"))
        check("version 0.7.1 > 0.7", Updater.isNewer("0.7.1", than: "0.7"))
        check("version equal is not newer", !Updater.isNewer("0.7.1", than: "0.7.1"))
        check("version older is not newer", !Updater.isNewer("0.6.9", than: "0.7.0"))
        check("selftest build is older than any release", Updater.isNewer("0.1.0", than: "0.0.0-selftest"))
    }

    // MARK: Interface, at every size and both fonts

    private func interface() async {
        guard let window = host.window else {
            check("interface: window", false, "no window")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        for font in [AppFont.system, .inter] {
            for size in UISize.allCases {
                let tag = "\(size.rawValue)/\(font.rawValue)"
                store.appFont = font
                store.uiSize = size
                reset()
                await settle(1.0)

                // Time travel by clicking an hour tile, the arrows and Now.
                await click("hour-Tokyo-2", in: window)
                check("\(tag) click hour +2", store.offsetHours == 2, "offset \(store.offsetHours)")
                await click("travel-now", in: window)
                check("\(tag) click Now", store.offsetHours == 0, "offset \(store.offsetHours)")
                await click("travel-later", in: window)
                check("\(tag) click later", store.offsetHours == 1, "offset \(store.offsetHours)")
                await click("travel-earlier", in: window)
                check("\(tag) click earlier", store.offsetHours == 0, "offset \(store.offsetHours)")

                // Add City: open, pick a search result.
                await click("control-add", in: window)
                check("\(tag) Add City opens search", adding.wrappedValue)
                let before = store.places.count
                await click("result-0", in: window)
                check("\(tag) click a result adds it", store.places.count == before + 1, "\(before) -> \(store.places.count)")
                await click("control-add", in: window)
                check("\(tag) Done closes search", !adding.wrappedValue)

                // Edit: reorder with the handle, delete with the button.
                await click("control-edit", in: window)
                check("\(tag) Edit on", editing.wrappedValue)
                let first = store.places[0].name
                let pitch = Metrics(scale: size.scale, family: font).rowHeight(compact: false) + Metrics(scale: size.scale).gutter
                await drag("handle-\(first)", by: pitch * 1.1, in: window)
                check("\(tag) drag handle moves a row down", store.places.firstIndex { $0.name == first } == 1,
                      store.places.map(\.name).joined(separator: ","))
                let last = store.places[store.places.count - 1].name
                let count = store.places.count
                await click("delete-\(last)", in: window)
                check("\(tag) delete removes the city", store.places.count == count - 1 && !store.places.contains { $0.name == last },
                      "\(count) -> \(store.places.count)")
                await click("control-edit", in: window)
                check("\(tag) Edit off", !editing.wrappedValue)

                // Twelve cities still fit on screen.
                reset((0..<ZoneStore.maxPlaces).map { ("City \($0)", ["UTC", "Asia/Kolkata", "America/Chicago"][$0 % 3]) })
                await settle(1.2)
                let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
                check("\(tag) 12 cities: window on screen", screen.insetBy(dx: -1, dy: -1).contains(window.frame),
                      "window \(Int(window.frame.width))x\(Int(window.frame.height)) screen \(Int(screen.width))x\(Int(screen.height))")
            }
        }
        store.appFont = .system
        store.uiSize = .medium
        reset()
    }

    // MARK: Accessibility-driven input

    /// Centre of a control in window coordinates, from the frame it reported while on screen.
    private func point(of id: String, in window: NSWindow) -> NSPoint? {
        guard let frame = TestAnchors.frames[id], let content = window.contentView, frame.width > 0 else {
            SelfTest.log("functional: no element \(id)")
            return nil
        }
        // SwiftUI's global space is the window's content, top-left origin.
        return NSPoint(x: frame.midX, y: content.bounds.height - frame.midY)
    }

    private func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ) else { return }
        window.sendEvent(event)
    }

    private func click(_ id: String, in window: NSWindow) async {
        guard let p = point(of: id, in: window) else { return }
        // Which view the window will deliver this click to (the frame view covers the title bar too).
        if let frameView = window.contentView?.superview {
            let hit = frameView.hitTest(frameView.convert(p, from: nil))
            SelfTest.log("functional: click \(id) at \(Int(p.x)),\(Int(p.y)) in \(Int(window.frame.width))x\(Int(window.frame.height)) -> \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        send(.leftMouseDown, at: p, in: window)
        try? await Task.sleep(for: .milliseconds(60))
        send(.leftMouseUp, at: p, in: window)
        await settle()
    }

    /// Drags vertically by `distance` points (positive is down the screen).
    private func drag(_ id: String, by distance: CGFloat, in window: NSWindow) async {
        guard let start = point(of: id, in: window) else { return }
        send(.leftMouseDown, at: start, in: window)
        for step in 1...8 {
            try? await Task.sleep(for: .milliseconds(40))
            send(.leftMouseDragged, at: NSPoint(x: start.x, y: start.y - distance * CGFloat(step) / 8), in: window)
        }
        send(.leftMouseUp, at: NSPoint(x: start.x, y: start.y - distance), in: window)
        await settle()
    }
}

/// Where each tagged control is on screen, recorded only while the self-test runs.
@MainActor
enum TestAnchors {
    static var frames: [String: CGRect] = [:]
}

extension View {
    /// An accessibility identifier, plus (in the self-test only) the control's frame so the
    /// functional test can click it.
    func testID(_ id: String) -> some View {
        accessibilityIdentifier(id)
            .background {
                if SelfTest.isActive {
                    Color.clear
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TestAnchors.frames[id] = $0 }
                        .onDisappear { TestAnchors.frames[id] = nil }
                }
            }
    }
}
