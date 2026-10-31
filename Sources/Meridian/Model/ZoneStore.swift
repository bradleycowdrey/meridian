import SwiftUI
import ServiceManagement
import AppKit
import WidgetKit

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, cityTime
    var id: String { rawValue }
    var label: String { self == .icon ? "Icon only" : "City and time" }
}

/// All app state. Settings persist to UserDefaults.
@MainActor
final class ZoneStore: ObservableObject {
    static let maxPlaces = 12

    @Published var places: [Place] { didSet { savePlaces(); syncWidget() } }

    /// The clock everything renders from; ticks every few seconds.
    @Published private(set) var now = Date()
    private var ticker: Timer?

    /// Time travel, in whole hours from now. Shared by the menu bar and the window.
    @Published var offsetHours = 0

    @Published var use24h: Bool { didSet { defaults.set(use24h, forKey: "use24h"); syncWidget() } }
    @Published var showWorkHours: Bool { didSet { defaults.set(showWorkHours, forKey: "showWorkHours") } }
    @Published var workStart: Int { didSet { defaults.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { defaults.set(workEnd, forKey: "workEnd") } }
    @Published var floatOnTop: Bool { didSet { defaults.set(floatOnTop, forKey: "floatOnTop") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var uiSize: UISize { didSet { defaults.set(uiSize.rawValue, forKey: "uiSize") } }
    @Published var appFont: AppFont { didSet { defaults.set(appFont.rawValue, forKey: "appFont") } }
    @Published var menuBarPlaceID: UUID? { didSet { defaults.set(menuBarPlaceID?.uuidString, forKey: "menuBarPlaceID") } }
    /// Keep a "My Location" row for the city you're in (on unless turned off in Settings).
    @Published var useMyLocation: Bool {
        didSet { MyLocation.chosen = true; defaults.set(useMyLocation, forKey: "useMyLocation"); updateMyLocation() }
    }
    private let locator = CityLocator()

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        } else {
            // Unreadable saved cities: keep a copy rather than overwrite them on the next edit.
            if let data = d.data(forKey: "places") { d.set(data, forKey: "places.backup") }
            places = ZoneStore.starterPlaces()
        }
        use24h = d.object(forKey: "use24h") as? Bool ?? true
        showWorkHours = d.object(forKey: "showWorkHours") as? Bool ?? true
        workStart = d.object(forKey: "workStart") as? Int ?? 9
        workEnd = d.object(forKey: "workEnd") as? Int ?? 18
        floatOnTop = d.object(forKey: "floatOnTop") as? Bool ?? false
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .icon
        menuBarPlaceID = d.string(forKey: "menuBarPlaceID").flatMap(UUID.init(uuidString:))
        uiSize = UISize(rawValue: d.string(forKey: "uiSize") ?? "") ?? .medium
        appFont = AppFont(rawValue: d.string(forKey: "appFont") ?? "") ?? .system
        // Off in the CI self-test: it drives a fixed list of cities, and a permission prompt
        // would cover the window.
        useMyLocation = SelfTest.isActive ? false : (d.object(forKey: "useMyLocation") as? Bool ?? true)
        updateMyLocation(locate: false)
        // Once the terms are agreed: ask whether to use my location (first launch only), then
        // look up the city.
        Task { @MainActor [weak self] in
            while !Terms.accepted { try? await Task.sleep(for: .seconds(1)) }
            guard let self else { return }
            if !MyLocation.chosen && !SelfTest.isActive { self.askAboutMyLocation() }
            self.updateMyLocation()
        }

        syncWidget()
        reloadWidgetsAfterUpdate()

        // Common run-loop mode, so the clock keeps ticking while a menu is open or during a drag.
        let ticker = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        // The Mac changed time zone (travel) or the date rolled over: refresh at once,
        // including the widget's "Today, +5 hr" lines.
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSCalendarDayChanged, NSWorkspace.didWakeNotification] {
            let center = name == NSWorkspace.didWakeNotification ? NSWorkspace.shared.notificationCenter : NotificationCenter.default
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    NSTimeZone.resetSystemTimeZone()
                    self?.now = Date()
                    if name == .NSSystemTimeZoneDidChange { self?.updateMyLocation() }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    func tick() {
        let date = Date()
        if Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
            || date.timeIntervalSince(now) > 60 {
            // Time travel is counted from the current hour; when the hour turns, shift the
            // offset so the hour being looked at stays put.
            let passed = Int((TimeMath.hourAnchor(date).timeIntervalSince(TimeMath.hourAnchor(now)) / 3600).rounded())
            if offsetHours != 0 && passed != 0 { offsetHours -= passed }
            now = date
        }
    }

    private static func starterPlaces() -> [Place] {
        let local = TimeZone.current.identifier
        let localName = local.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Here"
        var places = [Place(name: localName, timeZoneID: local)]
        for (name, id) in [("New York", "America/New_York"), ("London", "Europe/London"), ("Tokyo", "Asia/Tokyo")]
        where id != local {
            places.append(Place(name: name, timeZoneID: id))
        }
        return places
    }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) { defaults.set(data, forKey: "places") }
    }

    /// Hands the cities to the desktop widget and asks it to redraw when they changed.
    private func syncWidget() {
        let snapshot = WidgetSnapshot(
            cities: places.map { .init(name: $0.name, timeZoneID: $0.timeZoneID) },
            use24h: use24h
        )
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The first launch of a new version (after an update or reinstall) redraws the widgets at
    /// once, so they pick up the new widget code instead of waiting for their next timeline.
    private func reloadWidgetsAfterUpdate() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard defaults.string(forKey: "widgetsReloadedForBuild") != version else { return }
        WidgetCenter.shared.reloadAllTimelines()
        defaults.set(version, forKey: "widgetsReloadedForBuild")
    }

    // MARK: Places

    var canAdd: Bool { places.count < Self.maxPlaces }

    func add(_ entry: CityEntry) {
        guard canAdd, !contains(entry) else { return }
        places.append(Place(name: entry.name, timeZoneID: entry.timeZoneID))
    }

    /// Already tracking this city (same name and zone)?
    func contains(_ entry: CityEntry) -> Bool {
        places.contains { $0.name == entry.name && $0.timeZoneID == entry.timeZoneID }
    }

    func remove(_ place: Place) {
        // Deleting My Location turns it off, so it doesn't come straight back.
        if place.isMyLocation { MyLocation.forget(defaults: defaults) }
        places.removeAll { $0.id == place.id }
        if menuBarPlaceID == place.id { menuBarPlaceID = nil }
        if place.isMyLocation { useMyLocation = false }
    }

    /// Adds, updates or removes the My Location row, and (with `locate`) looks up the city name,
    /// which updates the row again when it arrives.
    func updateMyLocation(locate: Bool = true) {
        var list = places
        let on = useMyLocation && MyLocation.chosen
        if on {
            MyLocation.apply(to: &list, city: locator.city, defaults: defaults)
        } else {
            MyLocation.remove(from: &list, defaults: defaults)
        }
        if list != places { places = list }
        guard on, locate, Terms.accepted else { return }
        locator.locate { [weak self] in self?.updateMyLocation(locate: false) }
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
    }

    var menuBarPlace: Place? {
        places.first { $0.id == menuBarPlaceID } ?? places.first
    }

    /// The first-launch question. Use My Location is the default (recommended) answer.
    private func askAboutMyLocation() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = MyLocation.questionTitle
        alert.informativeText = MyLocation.questionMessage(device: "Mac")
        alert.addButton(withTitle: "Use My Location")
        alert.addButton(withTitle: "Not Now")
        useMyLocation = alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Size

    func stepSize(_ direction: Int) {
        let next = direction > 0 ? uiSize.larger : uiSize.smaller
        if let next { withAnimation(.snappy) { uiSize = next } }
    }

    // MARK: Time travel

    /// The moment being looked at: now, or a whole hour in the past/future.
    func selectedMoment() -> Date {
        offsetHours == 0 ? now : TimeMath.hourAnchor(now).addingTimeInterval(Double(offsetHours) * 3600)
    }

    func travel(_ hours: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { offsetHours += hours }
    }

    func backToNow() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { offsetHours = 0 }
    }

    func isWorkHour(_ hour: Int) -> Bool {
        // Same start and end means around the clock.
        if workStart == workEnd || (workStart == 0 && workEnd == 24) { return true }
        return workStart <= workEnd ? (hour >= workStart && hour < workEnd) : (hour >= workStart || hour < workEnd)
    }

    /// Plain-text summary of the selected moment, for pasting into a chat or invite.
    func copyMoment() {
        guard !places.isEmpty else { return }
        let moment = selectedMoment()
        let lines = places.map { place in
            "\(place.name): \(TimeMath.fullMoment(moment, in: place.timeZone, use24h: use24h)) (\(place.offsetLabel(at: moment)))"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Meridian: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }
}
