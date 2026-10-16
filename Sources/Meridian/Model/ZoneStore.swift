import SwiftUI
import ServiceManagement
import AppKit

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, cityTime
    var id: String { rawValue }
    var label: String { self == .icon ? "Icon only" : "City and time" }
}

/// All app state. Settings persist to UserDefaults.
@MainActor
final class ZoneStore: ObservableObject {
    static let maxPlaces = 12

    @Published var places: [Place] { didSet { savePlaces() } }

    /// The clock everything renders from; ticks every few seconds.
    @Published private(set) var now = Date()
    private var ticker: Timer?

    /// Time travel, in whole hours from now. Shared by the menu bar and the window.
    @Published var offsetHours = 0

    @Published var use24h: Bool { didSet { defaults.set(use24h, forKey: "use24h") } }
    @Published var showWorkHours: Bool { didSet { defaults.set(showWorkHours, forKey: "showWorkHours") } }
    @Published var workStart: Int { didSet { defaults.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { defaults.set(workEnd, forKey: "workEnd") } }
    @Published var floatOnTop: Bool { didSet { defaults.set(floatOnTop, forKey: "floatOnTop") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var uiSize: UISize { didSet { defaults.set(uiSize.rawValue, forKey: "uiSize") } }
    @Published var appFont: AppFont { didSet { defaults.set(appFont.rawValue, forKey: "appFont") } }
    @Published var menuBarPlaceID: UUID? { didSet { defaults.set(menuBarPlaceID?.uuidString, forKey: "menuBarPlaceID") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        } else {
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

        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        let date = Date()
        if Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now)
            || date.timeIntervalSince(now) > 60 {
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

    // MARK: Places

    var canAdd: Bool { places.count < Self.maxPlaces }

    func add(_ entry: CityEntry) {
        guard canAdd else { return }
        places.append(Place(name: entry.name, timeZoneID: entry.timeZoneID))
    }

    func remove(_ place: Place) {
        places.removeAll { $0.id == place.id }
        if menuBarPlaceID == place.id { menuBarPlaceID = nil }
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
    }

    var menuBarPlace: Place? {
        places.first { $0.id == menuBarPlaceID } ?? places.first
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
        workStart <= workEnd ? (hour >= workStart && hour < workEnd) : (hour >= workStart || hour < workEnd)
    }

    /// Plain-text summary of the selected moment, for pasting into a chat or invite.
    func copyMoment() {
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
