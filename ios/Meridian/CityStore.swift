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

    /// Time travel, in whole hours from the current hour.
    @Published var offsetHours = 0
    /// The clock everything renders from; updated when the minute changes.
    @Published private(set) var now = Date()

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    /// Demo mode (App Store screenshots): fixed cities, nothing saved.
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
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
        let date = Date()
        guard Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
            || abs(date.timeIntervalSince(now)) > 60 else { return }
        // Keep a travelled-to hour where it is when the clock passes the hour.
        let passed = Int((TimeMath.hourAnchor(date).timeIntervalSince(TimeMath.hourAnchor(now)) / 3600).rounded())
        if offsetHours != 0 && passed != 0 { offsetHours -= passed }
        now = date
    }

    /// The app came back to the front: catch up the clock and the widgets.
    func refresh() {
        NSTimeZone.resetSystemTimeZone()
        now = Date()
        WidgetCenter.shared.reloadAllTimelines()
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

    func remove(at offsets: IndexSet) { places.remove(atOffsets: offsets) }
    func move(from source: IndexSet, to destination: Int) { places.move(fromOffsets: source, toOffset: destination) }

    // MARK: Time travel

    /// The moment being looked at: now, or a whole hour in the past or future.
    var moment: Date {
        offsetHours == 0 ? now : TimeMath.hourAnchor(now).addingTimeInterval(Double(offsetHours) * 3600)
    }

    func travel(_ hours: Int) {
        withAnimation(.snappy) { offsetHours += hours }
    }

    func backToNow() {
        withAnimation(.snappy) { offsetHours = 0 }
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
