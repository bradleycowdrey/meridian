import SwiftUI
import WidgetKit

/// All iPhone app state. Settings persist to UserDefaults; the cities are also handed to the
/// widgets through the App Group (see WidgetSnapshot).
@MainActor
final class CityStore: ObservableObject {
    static let maxPlaces = 12

    @Published var places: [Place] { didSet { save(); syncWidgets() } }
    @Published var use24h: Bool { didSet { defaults.set(use24h, forKey: "use24h"); syncWidgets() } }
    @Published var showWorkHours: Bool { didSet { defaults.set(showWorkHours, forKey: "showWorkHours") } }
    @Published var workStart: Int { didSet { defaults.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { defaults.set(workEnd, forKey: "workEnd") } }
    /// Keep a "My Location" row for the city you're in (on unless turned off in Settings).
    @Published var useMyLocation: Bool {
        didSet { defaults.set(useMyLocation, forKey: "useMyLocation"); updateMyLocation() }
    }
    private let locator = CityLocator()

    /// Time travel, in minutes (whole quarter-hours) from the current quarter-hour; 0 is now.
    @Published private(set) var offsetMinutes = 0
    /// Counts the user's own moves through time (drags, buttons, the date picker), for haptics:
    /// the clock catching up never ticks.
    @Published private(set) var userMoves = 0
    /// The clock everything renders from; updated when the minute changes.
    @Published private(set) var now = Date()
    /// Demo mode's fixed moment: Tuesday 9 June 2026, 9:41 AM in San Francisco (matches the
    /// screenshots' status bar, and no city is mid daylight-saving change).
    private static let demoDate = Date(timeIntervalSince1970: 1_781_023_260)
    private var clock: Date { demo ? Self.demoDate : Date() }

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    /// Demo mode (App Store screenshots): fixed cities, nothing saved.
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo { now = Self.demoDate }
        let d = UserDefaults.standard
        if demo {
            places = [("San Francisco", "America/Los_Angeles"), ("New York", "America/New_York"), ("London", "Europe/London"),
                      ("Dubai", "Asia/Dubai"), ("Mumbai", "Asia/Kolkata"), ("Tokyo", "Asia/Tokyo")]
                .map { Place(name: $0.0, timeZoneID: $0.1) }
        } else if let data = d.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        } else {
            places = CityStore.starterPlaces()
        }
        use24h = demo ? false : (d.object(forKey: "use24h") as? Bool ?? !CityStore.localeUses12h)
        showWorkHours = d.object(forKey: "showWorkHours") as? Bool ?? true
        workStart = d.object(forKey: "workStart") as? Int ?? 9
        workEnd = d.object(forKey: "workEnd") as? Int ?? 18
        useMyLocation = demo ? false : (d.object(forKey: "useMyLocation") as? Bool ?? true)
        updateMyLocation(locate: false)
        syncWidgets()
        let ticker = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// 12- or 24-hour to match the phone's region, until the user chooses.
    private static var localeUses12h: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    private static func starterPlaces() -> [Place] {
        let local = TimeZone.current.identifier
        let localName = local.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Here"
        var places = [Place(name: localName, timeZoneID: local)]
        for (name, id) in [("New York", "America/New_York"), ("London", "Europe/London"), ("Tokyo", "Asia/Tokyo")] where id != local {
            places.append(Place(name: name, timeZoneID: id))
        }
        return places
    }

    func tick() {
        let date = clock
        guard Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
            || abs(date.timeIntervalSince(now)) > 60 else { return }
        // Keep a travelled-to time where it is when the clock passes a quarter-hour.
        let passed = Int((Self.quarter(date).timeIntervalSince(Self.quarter(now)) / 60).rounded())
        if offsetMinutes != 0 && passed != 0 { offsetMinutes -= passed }
        now = date
    }

    /// The app came back to the front: catch up the clock and the widgets.
    func refresh() {
        NSTimeZone.resetSystemTimeZone()
        now = clock
        updateMyLocation()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Adds, updates or removes the My Location row, and (with `locate`, once the terms are
    /// agreed) looks up the city name, which updates the row again when it arrives.
    func updateMyLocation(locate: Bool = true) {
        guard !demo else { return }
        var list = places
        if useMyLocation {
            MyLocation.apply(to: &list, city: locator.city, defaults: defaults)
        } else {
            MyLocation.remove(from: &list, defaults: defaults)
        }
        if list != places { places = list }
        guard useMyLocation, locate, Terms.accepted else { return }
        locator.locate { [weak self] in self?.updateMyLocation(locate: false) }
    }

    private func save() {
        guard !demo, let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: "places")
    }

    private func syncWidgets() {
        guard !demo else { return }
        let snapshot = WidgetSnapshot(cities: places.map { .init(name: $0.name, timeZoneID: $0.timeZoneID) }, use24h: use24h)
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Cities

    var canAdd: Bool { places.count < Self.maxPlaces }

    func contains(_ entry: CityEntry) -> Bool {
        places.contains { $0.name == entry.name && $0.timeZoneID == entry.timeZoneID }
    }

    func add(_ entry: CityEntry) {
        guard canAdd, !contains(entry) else { return }
        places.append(Place(name: entry.name, timeZoneID: entry.timeZoneID))
    }

    func remove(at offsets: IndexSet) {
        // Deleting My Location turns it off, so it doesn't come straight back.
        let removesMyLocation = offsets.contains { places[$0].isMyLocation }
        if removesMyLocation { MyLocation.forget(defaults: defaults) }
        places.remove(atOffsets: offsets)
        if removesMyLocation { useMyLocation = false }
    }
    func remove(_ place: Place) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        remove(at: IndexSet(integer: i))
    }

    func move(from source: IndexSet, to destination: Int) { places.move(fromOffsets: source, toOffset: destination) }

    // MARK: Time travel

    /// The moment being looked at: now, or a quarter-hour in the past or future.
    var moment: Date {
        offsetMinutes == 0 ? now : Self.quarter(now).addingTimeInterval(Double(offsetMinutes) * 60)
    }

    var isNow: Bool { offsetMinutes == 0 }

    /// Start of the quarter-hour. Every time zone's offset is a whole number of quarter-hours, so
    /// this is a quarter-hour boundary everywhere.
    static func quarter(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
    }

    /// Go to a moment (rounded to its quarter-hour).
    func jump(to date: Date, animated: Bool = true) {
        let minutes = Int((Self.quarter(date).timeIntervalSince(Self.quarter(now)) / 60).rounded())
        if animated { withAnimation(.snappy) { offsetMinutes = minutes } } else { offsetMinutes = minutes }
        userMoves += 1
    }

    /// Set the offset directly while dragging (no animation; the drag is the animation).
    func scrub(to minutes: Int) {
        guard minutes != offsetMinutes else { return }
        offsetMinutes = minutes
        userMoves += 1
        if !hasScrubbed { hasScrubbed = true }
    }

    /// Set after the first drag through time, so the "Drag to change the time" hint retires.
    @Published private(set) var hasScrubbed = UserDefaults.standard.bool(forKey: "hasScrubbed") {
        didSet { defaults.set(hasScrubbed, forKey: "hasScrubbed") }
    }

    /// True when the selected moment is on a whole hour on the user's clock.
    var onTheHour: Bool { Calendar.current.component(.minute, from: moment) == 0 }

    /// Step to the next or previous whole hour on the user's clock.
    func travel(_ hours: Int) {
        let anchor = TimeMath.hourAnchor(moment)
        let aligned = anchor == moment
        jump(to: anchor.addingTimeInterval(Double(hours < 0 && !aligned ? hours + 1 : hours) * 3600))
    }

    func backToNow() {
        withAnimation(.snappy) { offsetMinutes = 0 }
        userMoves += 1
    }

    func rename(_ place: Place, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[i].name = String(trimmed.prefix(40))
    }

    /// Cities outside working hours at the selected moment (empty when the setting is off).
    var outsideWorkHours: [Place] {
        guard showWorkHours else { return [] }
        return places.filter { !isWorkHour($0.calendar.component(.hour, from: moment)) }
    }

    func isWorkHour(_ hour: Int) -> Bool {
        if workStart == workEnd || (workStart == 0 && workEnd == 24) { return true }
        return workStart <= workEnd ? (hour >= workStart && hour < workEnd) : (hour >= workStart || hour < workEnd)
    }

    /// Plain text for the selected moment in every city, for pasting into a chat or invite.
    var momentText: String {
        places.map { "\($0.name): \(TimeMath.fullMoment(moment, in: $0.timeZone, use24h: use24h)) (\($0.offsetLabel(at: moment)))" }
            .joined(separator: "\n")
    }
}
