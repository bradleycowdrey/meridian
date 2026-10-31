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

    /// The device's zone, named after its city ("America/Los_Angeles" -> "Los Angeles").
    static var zoneName: String {
        TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "My Location"
    }

    /// Adds or updates the row. The first time, a city already in the list in this time zone
    /// becomes the row (keeping its place in the order) instead of being shown twice.
    static func apply(to places: inout [Place], city: String?, defaults: UserDefaults = .standard) {
        let zone = TimeZone.current.identifier
        if let i = places.firstIndex(where: \.isMyLocation) {
            let moved = places[i].timeZoneID != zone
            places[i].timeZoneID = zone
            if let city { places[i].name = city } else if moved { places[i].name = zoneName }
        } else if let i = places.firstIndex(where: { $0.timeZoneID == zone }) {
            defaults.set(places[i].name, forKey: adoptedKey)
            places[i].id = Place.myLocationID
            if let city { places[i].name = city }
        } else {
            defaults.removeObject(forKey: adoptedKey)
            places.insert(Place(id: Place.myLocationID, name: city ?? zoneName, timeZoneID: zone), at: 0)
        }
    }

    /// Takes the row out (the setting was turned off). A city the row took over goes back to
    /// being an ordinary city with its old name.
    static func remove(from places: inout [Place], defaults: UserDefaults = .standard) {
        guard let i = places.firstIndex(where: \.isMyLocation) else { return }
        if let name = defaults.string(forKey: adoptedKey) {
            places[i].id = UUID()
            places[i].name = name
        } else {
            places.remove(at: i)
        }
        defaults.removeObject(forKey: adoptedKey)
    }

    /// The user deleted the row itself: it goes, whatever it took over.
    static func forget(defaults: UserDefaults = .standard) {
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
