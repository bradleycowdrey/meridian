import SwiftUI
import WidgetKit

/// All iPhone app state. Settings persist to UserDefaults; the cities are also handed to the
/// widgets through the App Group (see WidgetSnapshot).
@MainActor
final class CityStore: ObservableObject {
    static let maxPlaces = 24
    /// The most custom groups the list keeps.
    static let maxGroups = 24

    @Published var places: [Place] { didSet { save(); syncWidgets() } }
    @Published var use24h: Bool { didSet { defaults.set(use24h, forKey: "use24h"); syncWidgets() } }
    @Published var showWorkHours: Bool { didSet { defaults.set(showWorkHours, forKey: "showWorkHours") } }
    @Published var workStart: Int { didSet { defaults.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { defaults.set(workEnd, forKey: "workEnd") } }
    /// Count public holidays as days off (Settings).
    @Published var countHolidays = Holidays.counted { didSet { Holidays.counted = countHolidays } }
    /// Group cities by continent automatically (Settings).
    @Published var continentGroups = Continent.autoGroups {
        didSet {
            Continent.autoGroups = continentGroups
            // A continent filter that no longer exists goes back to everyone.
            validateFilter()
        }
    }
    /// The group the list shows ("Design team"); nil shows everyone.
    @Published var groupFilter: String? = UserDefaults.standard.string(forKey: "groupFilter") {
        didSet { defaults.set(groupFilter, forKey: "groupFilter") }
    }
    /// The custom groups, in the user's order (the chips, Find a Time and the Groups screen follow
    /// it). A group stays here with no cities in it until it is deleted.
    @Published var groupOrder: [String] = [] {
        didSet { if !demo { defaults.set(groupOrder, forKey: "groupOrder") } }
    }
    /// Clock changes the user has closed the notice for ("Europe/London|1793000000").
    @Published var dismissedClockChanges = Set(UserDefaults.standard.stringArray(forKey: "dismissedClockChanges") ?? []) {
        didSet { defaults.set(Array(dismissedClockChanges), forKey: "dismissedClockChanges") }
    }
    /// Keep a "My Location" row for the city you're in (on unless turned off in Settings).
    @Published var useMyLocation: Bool {
        didSet {
            MyLocation.chosen = true
            locationChosen = true
            defaults.set(useMyLocation, forKey: "useMyLocation")
            updateMyLocation()
        }
    }
    private let locator = CityLocator()
    /// Answered the first-launch "Use your location?" question (or changed the setting).
    @Published private(set) var locationChosen = MyLocation.chosen

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
        // The groups' order: saved, or (from before it was kept) the cards' groups A to Z; any group
        // a card is in that the order lacks goes on the end.
        let cardGroups: [String] = places.flatMap { $0.groups ?? [] }
        var order: [String] = []
        if !demo {
            if let saved = d.stringArray(forKey: "groupOrder") {
                order = saved
            } else {
                order = Array(Set(cardGroups)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
        }
        for g in cardGroups where !order.contains(g) { order.append(g) }
        groupOrder = order
        // didSet doesn't run in init.
        if !demo { d.set(order, forKey: "groupOrder") }
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
        now = date
        // A picked time stays exactly where it is as the clock moves; a shift ("+2 hr") moves with it.
        if let pinned { offsetMinutes = Self.minutes(from: now, to: pinned) }
    }

    /// The app came back to the front: catch up the clock and the widgets.
    func refresh() {
        NSTimeZone.resetSystemTimeZone()
        now = clock
        updateMyLocation()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The card standing in for My Location (you already have a card in this time zone).
    @Published private(set) var myLocationHost: UUID?

    /// The card is where you are: the My Location card, or the one standing in for it.
    func isHere(_ place: Place) -> Bool { place.isMyLocation || place.id == myLocationHost }

    /// The city you're in, when Location Services has named it ("Boulder" while your card says Denver).
    var hereCity: String? { locator.city }

    /// Adds, updates or removes the My Location row, and (with `locate`, once the terms are
    /// agreed) looks up the city name, which updates the row again when it arrives.
    func updateMyLocation(locate: Bool = true) {
        guard !demo else { return }
        var list = places
        let on = useMyLocation && MyLocation.chosen
        if on {
            MyLocation.apply(to: &list, city: locator.city, defaults: defaults)
        } else {
            MyLocation.remove(from: &list, defaults: defaults)
        }
        if list != places { places = list }
        let host = on ? MyLocation.hostID(defaults: defaults) : nil
        if host != myLocationHost { myLocationHost = host }
        validateFilter()
        guard on, locate, Terms.accepted else { return }
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
        places.contains { $0.person == nil && $0.name == entry.name && $0.timeZoneID == entry.timeZoneID }
    }

    /// Adds a city; returns its card's id (nil if it wasn't added, or became My Location).
    @discardableResult func add(_ entry: CityEntry) -> UUID? {
        guard canAdd, !contains(entry) else { return nil }
        let place = Place(name: entry.name, timeZoneID: entry.timeZoneID, countryCode: entry.countryCode,
                          latitude: entry.latitude, longitude: entry.longitude)
        places.append(place)
        // A city in your own time zone becomes My Location, rather than showing twice.
        updateMyLocation(locate: false)
        return places.contains { $0.id == place.id } ? place.id : nil
    }

    func remove(at offsets: IndexSet) {
        // Deleting My Location turns it off, so it doesn't come straight back.
        let removesMyLocation = offsets.contains { places[$0].isMyLocation }
        if removesMyLocation { MyLocation.forget(defaults: defaults) }
        let removesHost = offsets.contains { places[$0].id == myLocationHost }
        places.remove(atOffsets: offsets)
        // Deleting the card standing in for My Location brings the My Location card back.
        if removesMyLocation { useMyLocation = false } else if removesHost { updateMyLocation(locate: false) }
        validateFilter()
    }
    func remove(_ place: Place) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        remove(at: IndexSet(integer: i))
    }

    func move(from source: IndexSet, to destination: Int) { places.move(fromOffsets: source, toOffset: destination) }

    // MARK: Time travel

    /// The moment being looked at: a picked time exactly (8:15:00 from the ruler, a tapped hour, a
    /// date), or now plus a shift ("+2 hr" is exactly two hours on).
    var moment: Date {
        pinned ?? now.addingTimeInterval(Double(offsetMinutes) * 60)
    }

    /// A picked clock time, kept exactly (not as minutes from now, which would round to the minute
    /// and land on 8:14 or 8:16); nil for now or a shift from now.
    private var pinned: Date?

    var isNow: Bool { pinned == nil && offsetMinutes == 0 }

    /// Whole minutes from one time to another, for the offset the views read.
    private static func minutes(from: Date, to: Date) -> Int { Int((to.timeIntervalSince(from) / 60).rounded()) }

    /// Pin a picked time (or let go of it at now).
    private func pin(_ date: Date?) {
        pinned = date
        offsetMinutes = date.map { Self.minutes(from: now, to: $0) } ?? 0
        if date != nil && offsetMinutes == 0 { offsetMinutes = date! > now ? 1 : -1 }   // still "away"
    }

    /// Start of the quarter-hour. Every time zone's offset is a whole number of quarter-hours, so
    /// this is a quarter-hour boundary everywhere.
    static func quarter(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
    }

    /// Go to a moment, which then stays put.
    func jump(to date: Date, animated: Bool = true) {
        if animated { withAnimation(.snappy) { pin(date) } } else { pin(date) }
        userMoves += 1
    }

    /// Look some minutes from now ("+3 hr"); it moves with the clock.
    func shift(minutes: Int) {
        pinned = nil
        withAnimation(.snappy) { offsetMinutes = minutes }
        userMoves += 1
    }

    /// The time ruler settled on a quarter-hour of the clock, which then stays put; the quarter-hour
    /// just begun stands for now.
    func scrub(toQuarter date: Date) {
        let atNow = abs(date.timeIntervalSince(Self.quarter(now))) < 1
        guard atNow ? !isNow : pinned != date else { return }
        pin(atNow ? nil : date)
        userMoves += 1
        if !hasScrubbed { hasScrubbed = true }
    }

    /// While dragging the slider or a day bar: the quarter-hour on the clock nearest to this many
    /// minutes from now (11:00, 11:15, 11:30), which then stays put as the clock moves.
    func scrub(toQuarterNear minutes: Double) {
        let target = now.addingTimeInterval(minutes * 60)
        let snapped = Date(timeIntervalSinceReferenceDate: (target.timeIntervalSinceReferenceDate / 900).rounded() * 900)
        let atNow = abs(minutes) < 7.5   // near the middle is Now
        guard atNow ? !isNow : pinned != snapped else { return }
        pin(atNow ? nil : snapped)
        userMoves += 1
        if !hasScrubbed { hasScrubbed = true }
    }

    /// Set the offset directly while dragging (no animation; the drag is the animation).
    func scrub(to minutes: Int) {
        guard minutes != offsetMinutes || pinned != nil else { return }
        pinned = nil
        offsetMinutes = minutes
        userMoves += 1
        if !hasScrubbed { hasScrubbed = true }
    }

    /// Set after the first drag through time, so the "Drag to change the time" hint retires.
    @Published private(set) var hasScrubbed = UserDefaults.standard.bool(forKey: "hasScrubbed") {
        didSet { defaults.set(hasScrubbed, forKey: "hasScrubbed") }
    }

    /// True when the selected moment is on a whole hour on the user's clock.
    var onTheHour: Bool { offsetMinutes % 60 == 0 || Calendar.current.component(.minute, from: moment) == 0 }

    /// Step to the next or previous whole hour on the user's clock.
    func travel(_ hours: Int) {
        let anchor = TimeMath.hourAnchor(moment)
        let aligned = anchor == moment
        jump(to: anchor.addingTimeInterval(Double(hours < 0 && !aligned ? hours + 1 : hours) * 3600))
    }

    func backToNow() {
        pinned = nil
        withAnimation(.snappy) { offsetMinutes = 0 }
        userMoves += 1
    }

    func rename(_ place: Place, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        // A person's card renames the person; a city's, the city.
        if places[i].person != nil { places[i].person = String(trimmed.prefix(40)) } else { places[i].name = String(trimmed.prefix(40)) }
    }

    /// Cities outside working hours at the selected moment (empty when the setting is off).
    var outsideWorkHours: [Place] {
        guard showWorkHours else { return [] }
        return places.filter { !isWorking($0, at: moment) }
    }

    func isWorkHour(_ hour: Int) -> Bool {
        WorkWeek.isWorkHour(hour, start: workStart, end: workEnd)
    }

    /// A working day and hour in this city (its own week and hours, or the usual ones there).
    func isWorking(_ place: Place, at date: Date) -> Bool {
        WorkWeek.isWorking(place, at: date, start: workStart, end: workEnd)
    }

    /// Sets a city's own working days and hours; nil goes back to the usual ones.
    func setWork(for place: Place, days: Set<Int>?, start: Int?, end: Int?) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[i].workDays = days
        places[i].workStart = start
        places[i].workEnd = end
    }

    /// Plain text for the selected moment in every city, for pasting into a chat or invite.
    var momentText: String {
        places.map { place in "\(place.person.map { "\($0) (\(place.name))" } ?? place.name): \(TimeMath.fullMoment(moment, in: place.timeZone, use24h: use24h)) (\(place.offsetLabel(at: moment)))" }
            .joined(separator: "\n")
    }
}
