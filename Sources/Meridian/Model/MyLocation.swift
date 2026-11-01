import Foundation
import CoreLocation

/// The "My Location" row: the city you're in, kept current when you travel (Mac and iPhone).
///
/// The row's time zone always comes from the device clock, so it's right even offline or with
/// Location Services off; Location Services only gives it its city name ("Boulder" rather than
/// "Denver"). Location is asked for once at launch and again when the time zone changes, never
/// tracked, and only the city name is kept, on the device.
enum MyLocation {
    private static let adoptedKey = "myLocation.adoptedName"

    /// Asked once, after the terms: use my location or not (the setting can change it later).
    /// Until then the row isn't added and Location Services isn't asked.
    static var chosen: Bool {
        get { UserDefaults.standard.bool(forKey: "myLocation.chosen") }
        set { UserDefaults.standard.set(newValue, forKey: "myLocation.chosen") }
    }

    /// The first-launch question, the same on Mac, iPhone and Android.
    static let questionTitle = "Use your location?"
    static func questionMessage(device: String) -> String {
        "Meridian can add the city you're in to your list, and keep it current when you travel. Recommended.\n\nYour location is only used to name the city, and Meridian keeps just that name, on your \(device). You can change this in Settings."
    }

    /// The device's zone, named after its city ("America/Los_Angeles" -> "Los Angeles").
    static var zoneName: String {
        TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "My Location"
    }

    private static let hostKey = "myLocation.hostID"

    /// The card that stands for where you are, when you already have a card in this time zone
    /// (then there's no separate My Location card, so nothing shows twice).
    static func hostID(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: hostKey).flatMap(UUID.init(uuidString:))
    }

    /// The card is where you are: the My Location card, or the card standing in for it.
    static func isHere(_ place: Place, defaults: UserDefaults = .standard) -> Bool {
        place.isMyLocation || place.id == hostID(defaults: defaults)
    }

    /// Shows where you are without showing anything twice. A card already in this time zone stands
    /// for it (marked My Location); otherwise there's a My Location card at the top, named after the
    /// city you're in, which follows you when you travel and folds back into your own card when you
    /// return.
    static func apply(to places: inout [Place], city: String?, defaults: UserDefaults = .standard) {
        restoreAdopted(&places, defaults: defaults)
        let zone = TimeZone.current.identifier
        if let host = places.first(where: { !$0.isMyLocation && $0.person == nil && $0.timeZoneID == zone }) {
            places.removeAll(where: \.isMyLocation)
            defaults.set(host.id.uuidString, forKey: hostKey)
            return
        }
        defaults.removeObject(forKey: hostKey)
        if let i = places.firstIndex(where: \.isMyLocation) {
            let moved = places[i].timeZoneID != zone
            places[i].timeZoneID = zone
            if let city { places[i].name = city } else if moved { places[i].name = zoneName }
        } else {
            places.insert(Place(id: Place.myLocationID, name: city ?? zoneName, timeZoneID: zone), at: 0)
        }
    }

    /// Takes My Location out (the setting was turned off): the card goes, and a card standing in
    /// for it is just a city again.
    static func remove(from places: inout [Place], defaults: UserDefaults = .standard) {
        restoreAdopted(&places, defaults: defaults)
        places.removeAll(where: \.isMyLocation)
        defaults.removeObject(forKey: hostKey)
    }

    /// The user deleted the My Location card (or the card standing in for it).
    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: adoptedKey)
        defaults.removeObject(forKey: hostKey)
    }

    /// Before 0.8.6 a city in your time zone was turned into the My Location card; give it back.
    private static func restoreAdopted(_ places: inout [Place], defaults: UserDefaults) {
        guard let name = defaults.string(forKey: adoptedKey) else { return }
        if let i = places.firstIndex(where: \.isMyLocation) {
            places[i].id = UUID()
            places[i].name = name
        }
        defaults.removeObject(forKey: adoptedKey)
    }
}

/// Finds the name of the city the device is in, with Location Services at city-level accuracy.
@MainActor
final class CityLocator: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private let geocoder = CLGeocoder()
    private var locating = false
    private var found: (() -> Void)?
    private let defaults = UserDefaults.standard

    /// The last city found, while the device is still in the same time zone.
    var city: String? {
        guard defaults.string(forKey: "myLocation.zone") == TimeZone.current.identifier else { return nil }
        return defaults.string(forKey: "myLocation.city")
    }

    /// Looks up the city (asking for permission the first time) and calls `found` when it has one.
    func locate(found: @escaping () -> Void) {
        self.found = found
        let manager = self.manager ?? CLLocationManager()
        if self.manager == nil {
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            self.manager = manager
        }
        start(manager)
    }

    private func start(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        default:
            guard !locating else { return }
            locating = true
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let manager = self.manager, self.found != nil, manager.authorizationStatus != .notDetermined else { return }
            self.start(manager)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.name(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.locating = false }
    }

    private func name(_ location: CLLocation) async {
        defer { locating = false }
        guard let place = try? await geocoder.reverseGeocodeLocation(location).first,
              let city = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea else { return }
        // A clock set to another zone than where it is: the row follows the clock, so its
        // zone's own name fits better than the city's.
        let zone = TimeZone.current.identifier
        if let placeZone = place.timeZone, placeZone.identifier != zone { return }
        defaults.set(city, forKey: "myLocation.city")
        defaults.set(zone, forKey: "myLocation.zone")
        found?()
    }
}
