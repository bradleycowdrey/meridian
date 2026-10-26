import AppIntents
import WidgetKit

// Edit Widget (touch and hold, or right-click on the Mac): "Use Meridian's Cities" on follows your
// list in the app; off, the widget shows the cities chosen for it.

/// A city you can pick for a widget: one of yours, or any city, airport code or time zone from
/// Meridian's search.
struct WidgetCity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static var defaultQuery = WidgetCityQuery()

    let name: String
    let timeZoneID: String
    var region: String = ""

    /// "London|Europe/London": the name and time zone are all a widget needs to remember.
    var id: String { "\(name)|\(timeZoneID)" }

    init(name: String, timeZoneID: String, region: String = "") {
        self.name = name
        self.timeZoneID = timeZoneID
        self.region = region
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, TimeZone(identifier: parts[1]) != nil else { return nil }
        self.init(name: parts[0], timeZoneID: parts[1])
    }

    var displayRepresentation: DisplayRepresentation {
        let zone = TimeZone(identifier: timeZoneID)
        let offset = zone.map { TimeMath.offsetLabel(seconds: $0.secondsFromGMT()) } ?? ""
        let place = region.isEmpty ? offset : "\(region.replacingOccurrences(of: "_", with: " ")) · \(offset)"
        return DisplayRepresentation(title: "\(name)", subtitle: "\(place)")
    }
}

struct WidgetCityQuery: EntityStringQuery {
    func entities(for identifiers: [WidgetCity.ID]) async throws -> [WidgetCity] {
        identifiers.compactMap(WidgetCity.init(id:))
    }

    /// Typing in the picker searches every city, airport code (SFO) and time zone (PST, UTC+5:30).
    func entities(matching string: String) async throws -> [WidgetCity] {
        CityDirectory.search(string).map { WidgetCity(name: $0.name, timeZoneID: $0.timeZoneID, region: $0.region) }
    }

    /// Before typing: your cities from Meridian, then a few well-known ones.
    func suggestedEntities() async throws -> [WidgetCity] {
        var cities = WidgetSnapshot.load().cities.map { WidgetCity(name: $0.name, timeZoneID: $0.timeZoneID) }
        for (name, id) in [("New York", "America/New_York"), ("London", "Europe/London"), ("Tokyo", "Asia/Tokyo"),
                           ("San Francisco", "America/Los_Angeles"), ("Paris", "Europe/Paris"), ("Sydney", "Australia/Sydney"),
                           ("Dubai", "Asia/Dubai"), ("Singapore", "Asia/Singapore"), ("Mumbai", "Asia/Kolkata")]
        where !cities.contains(where: { $0.timeZoneID == id && $0.name == name }) {
            cities.append(WidgetCity(name: name, timeZoneID: id))
        }
        return cities
    }
}

struct ClockConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Cities"
    static var description = IntentDescription("Show the cities from Meridian, or choose this widget's own.")

    @Parameter(title: "Use Meridian's Cities", default: true)
    var followApp: Bool

    @Parameter(title: "Cities")
    var cities: [WidgetCity]?

    /// The city picker only appears when the toggle is off.
    static var parameterSummary: some ParameterSummary {
        When(\.$followApp, .equalTo, true) {
            Summary {
                \.$followApp
            }
        } otherwise: {
            Summary {
                \.$followApp
                \.$cities
            }
        }
    }

    /// The snapshot this widget draws: the app's (for 12/24-hour time), with this widget's own
    /// cities when the toggle is off and some are chosen.
    func snapshot() -> WidgetSnapshot {
        var snapshot = WidgetSnapshot.load()
        if !followApp, let cities, !cities.isEmpty {
            snapshot.cities = cities.map { .init(name: $0.name, timeZoneID: $0.timeZoneID) }
        }
        return snapshot
    }
}
