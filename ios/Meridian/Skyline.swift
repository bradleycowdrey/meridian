import SwiftUI
import UIKit
import WidgetKit

/// The city cards: each city a rounded card filled with its skyline (the city's photo, or a
/// skyline drawn for it), shaded for the time of day there. Along the card's bottom, over a soft
/// dark scrim, its time, name, time zone and working status on the left and its five hour tiles on
/// the right, so the sky shows above them.
enum RowCard {
    static let radius: CGFloat = 16
    /// The thin band round the card's edge where its photo (and scrims) fade out to the list
    /// behind, so each card dissolves softly into the background instead of ending in a hard edge.
    static let edgeFeather: CGFloat = 6
    /// Between cards, and above the first and below the last.
    static let gap: CGFloat = 8
    /// A card's height once the list scrolls (six or more cities).
    static let scrollHeight: CGFloat = 132
    /// Up to this many cities share the screen's height; more scroll.
    static let maxFitCount = 5
    /// Shorter than this, the cards stop sharing the screen and scroll at `scrollHeight`.
    static let minFitHeight: CGFloat = 96
    /// The hour tiles' height (less when the card is short).
    static let tileHeight: CGFloat = 52
    /// The card's edge to its content: the content sits on the card's bottom.
    static let sidePadding: CGFloat = 14
    static let bottomPadding: CGFloat = 12
    static let topPadding: CGFloat = 8
    /// The time's size in tall cards and in compact ones.
    static let tallClock: CGFloat = 38
    static let compactClock: CGFloat = 26

    /// A tall card gets the large time and the status detail.
    static func isTall(_ row: CGFloat) -> Bool { row >= 150 }
}

/// A photo credit: who made it, its licence, and a link to it where it has one.
struct SkylinePhotoCredit: Codable, Hashable {
    var author: String?
    var license: String?
    var licenseUrl: String?
    var source: String?
}

/// One city of Resources/Data/skylines.json (written by the photo pipeline): its photo's key
/// (asset "Skyline-<key>", the day photo), the names it goes by, its time zone, the day photo's
/// credit, and (manifest v2) its night photo (asset "Skyline-<key>-night"), or none. Manifest v3
/// adds each photo's "focusX": where across it the city's landmark stands (0…1; missing: 0.5), and
/// optionally "top": how far down it the landmark's tip sits (0…1; missing: no tip rule). An entry
/// with "scene" ("coast": key "scenecoast", no names) is a default scene (plates-remote.json's
/// "scenes"): never matched by name and never listed in Photo Credits.
struct SkylineManifestEntry: Decodable {
    /// A city's night photo: its file, credit, skyline focus and landmark.
    struct Night: Decodable {
        var file: String?
        var credit: SkylinePhotoCredit?
        /// How far down the night photo its skyline band's centre sits (0…1), or nil.
        var focus: Double?
        /// Where across the night photo its landmark stands (0…1), or nil (v2: its centre).
        var focusX: Double?
        /// How far down the night photo its landmark's tip sits (0…1), or nil (no tip rule).
        var top: Double?

        private enum CodingKeys: String, CodingKey { case file, credit, focus, focusX, top }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            file = try? c.decodeIfPresent(String.self, forKey: .file)
            credit = try? c.decodeIfPresent(SkylinePhotoCredit.self, forKey: .credit)
            focus = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focus))
            focusX = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focusX))
            top = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .top))
        }
    }

    let key: String
    var names: [String] = []
    var zone: String?
    var file: String?
    var credit: SkylinePhotoCredit?
    /// nil in a v1 manifest, or when the pipeline found no night photo for the city.
    var night: Night?
    /// How far down the day photo its skyline band's centre sits (0…1), or nil (not measured).
    var focus: Double?
    /// Where across the day photo its landmark stands (0…1), or nil (v2: its centre).
    var focusX: Double?
    /// How far down the day photo its landmark's tip sits (0…1), or nil (no tip rule).
    var top: Double?
    /// A default scene's name ("coast"), or nil for a city's photo.
    var scene: String?

    private enum CodingKeys: String, CodingKey { case key, names, zone, file, credit, night, focus, focusX, top, scene }

    /// A focus within 0…1, or nil when missing or not a number.
    static func unitFocus(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
        zone = try? c.decodeIfPresent(String.self, forKey: .zone)
        file = try? c.decodeIfPresent(String.self, forKey: .file)
        credit = try? c.decodeIfPresent(SkylinePhotoCredit.self, forKey: .credit)
        night = try? c.decodeIfPresent(Night.self, forKey: .night)
        focus = Self.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focus))
        focusX = Self.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focusX))
        top = Self.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .top))
        scene = (try? c.decodeIfPresent(String.self, forKey: .scene)).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A manifest entry that failed to decode is skipped rather than losing the whole manifest.
struct LenientManifestItem<Item: Decodable>: Decodable {
    let item: Item?
    init(from decoder: Decoder) throws { item = try? Item(from: decoder) }
}

/// skylines.json as a whole: a bare list of cities (manifest v1 and v2), or (v3) an object with
/// "version": 3 and the list under "cities" (or "entries", "skylines", "photos", "items"; else the
/// first key holding a list of cities). Entries that fail to decode are skipped.
struct SkylineManifestFile<Item: Decodable>: Decodable {
    let version: Int?
    let items: [Item]

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([LenientManifestItem<Item>].self) {
            version = nil
            items = list.compactMap(\.item)
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        version = AnyKey(stringValue: "version").flatMap { try? c.decodeIfPresent(Int.self, forKey: $0) }
        let preferred = ["cities", "entries", "skylines", "photos", "items"]
        let keys = preferred.compactMap { AnyKey(stringValue: $0) }.filter { c.contains($0) }
            + c.allKeys.filter { !preferred.contains($0.stringValue) }
        for key in keys {
            if let list = try? c.decode([LenientManifestItem<Item>].self, forKey: key) {
                let found = list.compactMap(\.item)
                if !found.isEmpty {
                    items = found
                    return
                }
            }
        }
        items = []
    }

    /// The bundled skylines.json's entries, or nil when it is missing or unreadable.
    static func bundled() -> [Item]? {
        guard let url = Bundle.main.url(forResource: "skylines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SkylineManifestFile<Item>.self, from: data) else { return nil }
        return file.items
    }
}

/// A hosted AI plate of Resources/Data/plates-remote.json ("plates"): 1536×512 as the built-in
/// ones, downloaded once from `base + key + "-day.jpg"` and `base + key + "-night.jpg"`, with its
/// metro's name and each image's focus, landmark (focusX) and landmark tip (top), as skylines.json
/// gives them for a built-in plate.
struct RemotePlateEntry: Decodable, Sendable {
    struct Night: Decodable, Sendable {
        var focus: Double?
        var focusX: Double?
        var top: Double?

        private enum CodingKeys: String, CodingKey { case focus, focusX, top }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            focus = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focus))
            focusX = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focusX))
            top = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .top))
        }
    }

    let key: String
    var name: String?
    var focus: Double?
    var focusX: Double?
    var top: Double?
    var night: Night?

    private enum CodingKeys: String, CodingKey { case key, name, focus, focusX, top, night }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        focus = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focus))
        focusX = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focusX))
        top = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .top))
        night = try? c.decodeIfPresent(Night.self, forKey: .night)
    }
}

/// A metro centre of plates-remote.json ("metros"): its photo's key (built in or hosted), its
/// country (ISO code), where its centre is, and how far from it (km) it reaches.
struct RemoteMetro: Decodable, Sendable {
    let key: String
    let cc: String
    let lat: Double
    let lon: Double
    let r: Double
}

/// A default-scene rule of plates-remote.json ("scenes"): the scene ("coast": the built-in photo
/// "scenecoast") for a card whose time zone is in `zones`, or starts with `prefix`, or whose
/// |latitude| is at most `maxAbsLat`. A rule without any of them fits every card.
struct RemoteSceneRule: Decodable, Sendable {
    let scene: String
    var zones: [String]?
    var prefix: String?
    var maxAbsLat: Double?
}

/// A member town of a metro (plates-remote.json's "towns"): its name, the metro's photo key, and where it is.
struct RemoteTown: Sendable {
    let name: String
    let key: String
    let lat: Double
    let lon: Double
}

/// plates-remote.json (version 2) as a whole: {"version": 2, "base": "<url>/", "plates": [...],
/// "metros": [...], "towns": {key: [name, lat, lon, name, lat, lon, ...]}, "scenes": [...]}.
/// Entries that fail to decode are skipped. See scripts/photo-index.py.
struct RemotePlatesFile: Decodable, Sendable {
    var version: Int?
    var base: String?
    var plates: [RemotePlateEntry] = []
    var metros: [RemoteMetro] = []
    var towns: [RemoteTown] = []
    var scenes: [RemoteSceneRule] = []

    private enum CodingKeys: String, CodingKey { case version, base, plates, metros, towns, scenes }

    /// One value of a town list: a name or a coordinate (anything else is neither).
    private struct TownField: Decodable {
        var text: String?
        var number: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) {
                number = n
            } else {
                text = try? c.decode(String.self)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        base = try? c.decodeIfPresent(String.self, forKey: .base)
        plates = ((try? c.decodeIfPresent([LenientManifestItem<RemotePlateEntry>].self, forKey: .plates)) ?? [])
            .compactMap(\.item)
        metros = ((try? c.decodeIfPresent([LenientManifestItem<RemoteMetro>].self, forKey: .metros)) ?? [])
            .compactMap(\.item)
        scenes = ((try? c.decodeIfPresent([LenientManifestItem<RemoteSceneRule>].self, forKey: .scenes)) ?? [])
            .compactMap(\.item)
        let lists = (try? c.decodeIfPresent([String: [TownField]].self, forKey: .towns)) ?? [:]
        var towns: [RemoteTown] = []
        for (key, fields) in lists.sorted(by: { $0.key < $1.key }) {
            var i = 0
            while i + 2 < fields.count {
                if let name = fields[i].text, let lat = fields[i + 1].number, let lon = fields[i + 2].number {
                    towns.append(RemoteTown(name: name, key: key, lat: lat, lon: lon))
                }
                i += 3
            }
        }
        self.towns = towns
    }
}

/// Which photo a city without a built-in one of its own shows (Resources/Data/plates-remote.json;
/// the same order on every platform): the photo of the metro its town belongs to ("towns"), else of
/// the metro centre whose reach covers it ("metros"), when that photo is built in or a hosted AI
/// plate ("plates", downloaded once by CityPhotos); else a default scene ("scenes").
enum RemotePlates {
    /// The bundled index, or nil when it is missing or unreadable.
    static let file: RemotePlatesFile? = {
        guard let url = Bundle.main.url(forResource: "plates-remote", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RemotePlatesFile.self, from: data)
    }()

    /// Where the images live (ends in "/"), or nil without an index.
    private static let base: String? = {
        guard let raw = file?.base?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw.lowercased().hasPrefix("https://") else { return nil }
        return raw.hasSuffix("/") ? raw : raw + "/"
    }()

    /// Every hosted plate's credit (no source link).
    static let credit = SkylinePhotoCredit(author: "Generated with AI for Meridian", license: "AI-generated image",
                                           licenseUrl: nil, source: nil)

    /// The hosted plates by key (the first of each).
    static let byKey: [String: RemotePlateEntry] = {
        var out: [String: RemotePlateEntry] = [:]
        for entry in file?.plates ?? [] where out[entry.key] == nil { out[entry.key] = entry }
        return out
    }()

    /// The metro centres' countries by key (the first of each), upper case.
    private static let metroCountry: [String: String] = {
        var out: [String: String] = [:]
        for metro in file?.metros ?? [] where out[metro.key] == nil { out[metro.key] = metro.cc.uppercased() }
        return out
    }()

    /// The member towns by name (`townName`).
    private static let towns: [String: [RemoteTown]] = {
        var out: [String: [RemoteTown]] = [:]
        for town in file?.towns ?? [] {
            let n = townName(town.name)
            guard !n.isEmpty else { continue }
            out[n, default: []].append(town)
        }
        return out
    }()

    /// The default-scene rules, in order.
    static var scenes: [RemoteSceneRule] { file?.scenes ?? [] }

    /// How far a town may be from the card and still be its town, in km.
    static let townReach = 25.0

    /// A name as towns are matched: SkylineArt.normalize, then letters and digits only
    /// ("Saint-Étienne" and "Saint Etienne" alike).
    static func townName(_ name: String) -> String {
        String(SkylineArt.normalize(name).filter { $0.isLetter || $0.isNumber })
    }

    /// Great-circle distance in km.
    static func km(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let rad = Double.pi / 180
        let dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * rad) * cos(lat2 * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * asin(min(1, sqrt(h)))
    }

    /// The card's country (ISO code, upper case): its own, else its time zone's
    /// (WorkWeek.countryByZone, for older cards and widget-chosen cities that have none), or nil.
    static func country(_ place: Place) -> String? {
        let own = place.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let cc = own.isEmpty ? (WorkWeek.countryByZone[place.timeZoneID]?.uppercased() ?? "") : own
        return cc.isEmpty ? nil : cc
    }

    /// The card's coordinates: its latitude and longitude together, finite and in range; else
    /// nil (a lone latitude counts for nothing).
    static func coordinates(_ place: Place) -> (lat: Double, lon: Double)? {
        guard let lat = place.latitude, let lon = place.longitude, lat.isFinite, lon.isFinite,
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat, lon)
    }

    /// Step 2: the metro of the card's town. With coordinates, the nearest member town of the same
    /// name within 25 km; without, the one town of that name whose metro is in the card's country.
    static func townKey(for place: Place) -> String? {
        let candidates = towns[townName(place.name)] ?? []
        guard !candidates.isEmpty else { return nil }
        if case let (lat, lon)? = coordinates(place) {
            var best: (key: String, km: Double)?
            for town in candidates {
                let d = km(lat, lon, town.lat, town.lon)
                if d <= townReach, d < (best?.km ?? .infinity) { best = (town.key, d) }
            }
            return best?.key
        }
        guard let cc = country(place) else { return nil }
        let keys = Set(candidates.filter { metroCountry[$0.key] == cc }.map(\.key))
        return keys.count == 1 ? keys.first : nil
    }

    /// Step 3: the nearest metro centre in the card's country whose reach covers it (needs the
    /// card's coordinates and country).
    static func metroKey(for place: Place) -> String? {
        guard case let (lat, lon)? = coordinates(place), let cc = country(place) else { return nil }
        var best: (key: String, km: Double)?
        for metro in file?.metros ?? [] where metro.cc.uppercased() == cc {
            let d = km(lat, lon, metro.lat, metro.lon)
            if d <= metro.r, d < (best?.km ?? .infinity) { best = (metro.key, d) }
        }
        return best?.key
    }

    /// Whether a key is a hosted plate that can be downloaded.
    static func isHosted(_ key: String) -> Bool {
        base != nil && byKey[key] != nil
    }

    /// Whether a scene rule fits the card: its zone is listed, or starts with the prefix, or its
    /// |latitude| is at most maxAbsLat (only with coordinates, latitude and longitude both); a rule
    /// without conditions always fits.
    static func fits(_ rule: RemoteSceneRule, _ place: Place) -> Bool {
        var conditional = false
        if let zones = rule.zones {
            conditional = true
            if zones.contains(place.timeZoneID) { return true }
        }
        if let prefix = rule.prefix {
            conditional = true
            if !prefix.isEmpty, place.timeZoneID.hasPrefix(prefix) { return true }
        }
        if let maxAbsLat = rule.maxAbsLat {
            conditional = true
            if let lat = coordinates(place)?.lat, maxAbsLat >= abs(lat) { return true }
        }
        return !conditional
    }

    /// A hosted plate image: base + key + "-day.jpg" / "-night.jpg".
    static func imageURL(_ key: String, night: Bool) -> URL? {
        guard let base, !key.isEmpty,
              let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: base + escaped + (night ? "-night.jpg" : "-day.jpg"))
    }

    /// A hosted photo's focus, landmark and landmark tip for its SkylinePhoto id ("p:<key>" by
    /// day, "p:<key>-night" by night: the night entry's, else the day's), or nil for any other id.
    static func placement(forID id: String) -> (focus: Double?, focusX: Double?, top: Double?)? {
        guard id.hasPrefix("p:") else { return nil }
        let rest = String(id.dropFirst(2))
        if rest.hasSuffix("-night"), let entry = byKey[String(rest.dropLast(6))] {
            return placement(entry, night: true)
        }
        return byKey[rest].map { placement($0, night: false) }
    }

    /// An entry's day placement, or its night one (the day's where the night entry has none).
    static func placement(_ entry: RemotePlateEntry, night: Bool) -> (focus: Double?, focusX: Double?, top: Double?) {
        guard night, let n = entry.night else { return (entry.focus, entry.focusX, entry.top) }
        return (n.focus ?? entry.focus, n.focusX ?? entry.focusX, n.top ?? entry.top)
    }
}

/// A photo for a card, and a name for it that stays the same (for the ink cache). `night` is a
/// real night photo, shown as taken (never tinted).
struct SkylinePhoto {
    let id: String
    let image: UIImage
    var night = false
    /// How far down the photo its skyline band's centre sits (0…1), from the manifest (or a
    /// hosted plate's entry); nil when not measured (laid out at SkylineArt.defaultFocus).
    var focus: Double? = nil
    /// Where across the photo its landmark stands (0…1), from the manifest's "focusX"; nil for a
    /// v2 manifest (its centre).
    var focusX: Double? = nil
    /// How far down the photo its landmark's tip sits (0…1), from the manifest's "top"; nil when
    /// unknown (no tip rule: placed as before).
    var top: Double? = nil
}

/// A credit as Settings → About → Photo Credits lists it.
struct PhotoCreditItem: Identifiable, Hashable {
    let id: String
    let city: String
    let author: String?
    let license: String?
    let source: URL?
    /// Shown when there is no author or licence (the photo's file name).
    var fallback: String?
}

/// The skyline photos bundled with the app, by city, and their credits.
enum SkylineArt {
    /// Sky.phase, widened so the hour after sunrise and the hour after sunset are twilight too.
    static func phase(for place: Place, at date: Date) -> Sky.Phase {
        let now = Sky.phase(for: place, at: date)
        let hourAgo = Sky.phase(for: place, at: date.addingTimeInterval(-3600))
        return (now != .twilight && hourAgo != now) ? .twilight : now
    }

    // MARK: The manifest

    /// skylines.json from the app bundle, or nil until the photo pipeline has added it.
    static let manifest: [SkylineManifestEntry]? = {
        guard let entries = SkylineManifestFile<SkylineManifestEntry>.bundled() else { return nil }
        return entries.isEmpty ? nil : entries
    }()

    /// The manifest's entries by every name they go by (normalised). Default scenes go by none.
    private static let index: [String: [SkylineManifestEntry]] = {
        var out: [String: [SkylineManifestEntry]] = [:]
        for entry in manifest ?? [] where entry.scene == nil {
            var names = entry.names
            if names.isEmpty { names = [entry.key] }
            for name in names {
                let n = normalize(name)
                guard !n.isEmpty else { continue }
                out[n, default: []].append(entry)
            }
        }
        return out
    }()

    /// The manifest's entries by key (the first of each).
    private static let byKey: [String: SkylineManifestEntry] = {
        var out: [String: SkylineManifestEntry] = [:]
        for entry in manifest ?? [] where out[entry.key] == nil { out[entry.key] = entry }
        return out
    }()

    /// Lowercased, without accents or spaces at the ends ("São Paulo" -> "sao paulo").
    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The four photos from before the manifest, by name.
    private static func legacyKey(for name: String) -> String? {
        switch normalize(name) {
        case "san francisco": return "sanfrancisco"
        case "new york", "new york city", "manhattan": return "newyork"
        case "london": return "london"
        case "tokyo": return "tokyo"
        default: return nil
        }
    }

    /// Whether a manifest entry's time zone fits the card: the same zone, or one on the same
    /// clock all year (Asia/Calcutta and Asia/Kolkata); never Portland, Maine for Portland, Oregon.
    /// A zone this device doesn't know fits no other (as on Android).
    private static func zoneFits(_ zone: String?, _ place: Place) -> Bool {
        guard let zone, !zone.isEmpty, zone != place.timeZoneID else { return true }
        guard let tz = TimeZone(identifier: zone), let cardZone = TimeZone(identifier: place.timeZoneID) else { return false }
        // Compared on two fixed dates (mid-January and mid-July 2026), so only zones that keep the
        // same time all year (an old name for the same zone) match, not ones that agree just today.
        let dates = [Date(timeIntervalSince1970: 1768478400), Date(timeIntervalSince1970: 1784116800)]
        return dates.allSatisfy { tz.secondsFromGMT(for: $0) == cardZone.secondsFromGMT(for: $0) }
    }

    /// Guards the caches below (cards resolve on the main thread, the photo store off it).
    private static let cacheLock = NSLock()
    /// Answers so far, by name and zone ("" for none).
    private static var keyCache: [String: String] = [:]

    /// The bundled photo's key for a card by its city's name (for a person their city's), or nil.
    static func key(for place: Place) -> String? {
        let cacheKey = place.name + "|" + place.timeZoneID
        cacheLock.lock()
        let hit = keyCache[cacheKey]
        cacheLock.unlock()
        if let hit { return hit.isEmpty ? nil : hit }
        let result: String?
        if manifest == nil {
            result = legacyKey(for: place.name)
        } else {
            let candidates = index[normalize(place.name)] ?? []
            let exact = candidates.first(where: { $0.zone == place.timeZoneID })
            result = (exact ?? candidates.first(where: { zoneFits($0.zone, place) }))?.key
        }
        cacheLock.lock()
        if keyCache.count > 400 { keyCache.removeAll() }
        keyCache[cacheKey] = result ?? ""
        cacheLock.unlock()
        return result
    }

    /// Which photo a card shows (see RemotePlates and scripts/photo-index.py; the same on every
    /// platform): `key`, a built-in photo (the city's own by name, else its town's or metro's);
    /// else `hosted`, its town's or metro's hosted AI plate (shown once downloaded, with downloads
    /// on); and `scene`, its default scene's built-in key ("scenecoast"), shown when there is
    /// neither (or while the hosted plate isn't there).
    struct PhotoChoice: Equatable, Sendable {
        var key: String?
        var hosted: String?
        var scene: String?
    }

    /// Choices so far, by name, zone, country and place.
    private static var choiceCache: [String: PhotoChoice] = [:]

    /// The card's photo choice (cached).
    static func choice(for place: Place) -> PhotoChoice {
        let cacheKey = [place.name, place.timeZoneID, place.countryCode ?? "",
                        place.latitude.map { String($0) } ?? "", place.longitude.map { String($0) } ?? ""]
            .joined(separator: "|")
        cacheLock.lock()
        let hit = choiceCache[cacheKey]
        cacheLock.unlock()
        if let hit { return hit }
        let result = resolve(place)
        cacheLock.lock()
        if choiceCache.count > 400 { choiceCache.removeAll() }
        choiceCache[cacheKey] = result
        cacheLock.unlock()
        return result
    }

    /// Whether a key is a city's built-in photo (not a default scene).
    private static func isBuiltIn(_ key: String) -> Bool {
        guard let entry = byKey[key] else { return false }
        return entry.scene == nil
    }

    /// 1. the built-in photo by name; 2. its town's metro; 3. the metro centre covering it (each
    /// only when that photo is built in or hosted); 4. its default scene.
    private static func resolve(_ place: Place) -> PhotoChoice {
        let scene = sceneKey(for: place)
        if let own = key(for: place) { return PhotoChoice(key: own, hosted: nil, scene: scene) }
        if let town = RemotePlates.townKey(for: place) {
            if isBuiltIn(town) { return PhotoChoice(key: town, hosted: nil, scene: scene) }
            if RemotePlates.isHosted(town) { return PhotoChoice(key: nil, hosted: town, scene: scene) }
        }
        if let metro = RemotePlates.metroKey(for: place) {
            if isBuiltIn(metro) { return PhotoChoice(key: metro, hosted: nil, scene: scene) }
            if RemotePlates.isHosted(metro) { return PhotoChoice(key: nil, hosted: metro, scene: scene) }
        }
        return PhotoChoice(key: nil, hosted: nil, scene: scene)
    }

    /// The card's default scene: the first rule of plates-remote.json's "scenes" that fits it, as
    /// "scene<name>"; nil without one, or when that scene isn't built in (as on Android and the Mac).
    static func sceneKey(for place: Place) -> String? {
        guard let rule = RemotePlates.scenes.first(where: { RemotePlates.fits($0, place) }) else { return nil }
        let key = "scene" + rule.scene
        return byKey[key]?.scene != nil ? key : nil
    }

    /// A built-in photo (asset "Skyline-<key>", or its night photo "Skyline-<key>-night"), placed
    /// by its manifest entry; nil when the asset isn't there.
    private static func builtInPhoto(_ key: String, night: Bool) -> SkylinePhoto? {
        if night {
            return UIImage(named: "Skyline-\(key)-night").map {
                SkylinePhoto(id: "b:" + key + "-night", image: $0, night: true, focus: byKey[key]?.night?.focus,
                             focusX: byKey[key]?.night?.focusX, top: byKey[key]?.night?.top)
            }
        }
        return UIImage(named: "Skyline-\(key)").map {
            SkylinePhoto(id: "b:" + key, image: $0, focus: byKey[key]?.focus, focusX: byKey[key]?.focusX,
                         top: byKey[key]?.top)
        }
    }

    /// A downloaded hosted plate, placed by its plates-remote.json entry as a built-in plate is.
    private static func hostedPhoto(_ key: String, image: UIImage, night: Bool) -> SkylinePhoto {
        let p = RemotePlates.byKey[key].map { RemotePlates.placement($0, night: night) }
        return SkylinePhoto(id: "p:" + key + (night ? "-night" : ""), image: image, night: night,
                            focus: p?.focus, focusX: p?.focusX, top: p?.top)
    }

    /// The card's day photo (`night` false) or night photo, by its choice: the built-in photo; else
    /// its hosted plate when `plate` (the downloaded day image) is there, with `plateNight` after
    /// dark; else its default scene. nil by day: draw one; nil by night: no night photo (the day
    /// photo is darkened).
    private static func pick(_ place: Place, plate: UIImage?, plateNight: UIImage?, night: Bool) -> SkylinePhoto? {
        let chosen = choice(for: place)
        if let key = chosen.key, UIImage(named: "Skyline-\(key)") != nil { return builtInPhoto(key, night: night) }
        if let hosted = chosen.hosted, let plate {
            guard night else { return hostedPhoto(hosted, image: plate, night: false) }
            return plateNight.map { hostedPhoto(hosted, image: $0, night: true) }
        }
        if let scene = chosen.scene, UIImage(named: "Skyline-\(scene)") != nil { return builtInPhoto(scene, night: night) }
        return nil
    }

    /// The card's day photo: built in, its hosted plate (`plate`: the downloaded day image, nil
    /// when it isn't there or downloads are off), or its default scene; nil to draw one.
    static func photo(for place: Place, plate: UIImage? = nil) -> SkylinePhoto? {
        pick(place, plate: plate, plateNight: nil, night: false)
    }

    /// The card's night photo, paired with its day photo: a built-in day photo (or scene) takes its
    /// own night photo ("Skyline-<key>-night"), a hosted plate its downloaded night plate
    /// (`plateNight`). nil when there is none (the day photo is then darkened at night).
    static func nightPhoto(for place: Place, plate: UIImage? = nil, plateNight: UIImage? = nil) -> SkylinePhoto? {
        pick(place, plate: plate, plateNight: plateNight, night: true)
    }

    /// Whether the card wants its night photo: from sunset until an hour before sunrise (Sky's own
    /// night). The hour before sunrise, and the hour after it, keep the day photo with its warm
    /// twilight tint; so does the hour before sunset.
    static func wantsNight(_ place: Place, at date: Date) -> Bool {
        switch Sun.phase(place, at: date) {
        case .night(let rises)?: return rises.timeIntervalSince(date) >= 3600
        case .allNight?: return true
        case .day?, .allDay?: return false
        case nil: return Sky.phase(for: place, at: date) == .night
        }
    }

    /// The card's photo at a moment: by day its day photo; after dark its night photo when it has
    /// one, else the day photo (darkened for night), so the photo always fills the card, as the
    /// widget's. `plate` and `plateNight`: the card's downloaded hosted plate images (nil when not
    /// there, or downloads are off). nil to draw one.
    static func photo(for place: Place, at date: Date, plate: UIImage?, plateNight: UIImage?) -> SkylinePhoto? {
        guard let day = photo(for: place, plate: plate) else { return nil }
        guard wantsNight(place, at: date) else { return day }
        return nightPhoto(for: place, plate: plate, plateNight: plateNight) ?? day
    }

    /// A file-safe name for a card's widget copy: its city and time zone.
    static func slug(for place: Place) -> String {
        let raw = normalize(place.name) + "_" + place.timeZoneID.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        return String(raw.map { allowed.contains($0) ? $0 : "-" })
    }

    // MARK: Credits

    /// The four photos from before the manifest (AI-generated, no source link).
    private static let legacyCredits: [PhotoCreditItem] = ["London", "New York", "San Francisco", "Tokyo"].map { city in
        PhotoCreditItem(id: "b:" + city, city: city, author: RemotePlates.credit.author,
                        license: RemotePlates.credit.license, source: nil, fallback: nil)
    }

    /// A credit's link, or nil when it has none: a missing, empty or non-web "source" (the AI
    /// plates' credits carry "source": "" and no licenseUrl), so no broken link is shown.
    static func creditLink(_ source: String?) -> URL? {
        guard let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    /// Whether a credit is an AI-generated plate's ("Generated with AI for Meridian").
    static func isGenerated(_ credit: PhotoCreditItem) -> Bool {
        let text = [credit.author, credit.license].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("generated with ai") || text.contains("ai-generated")
    }

    /// Settings → About's note beside Photo Credits: where the built-in photos come from.
    static var creditsSummary: String { "Generated with AI" }

    /// The bundled photos' credits (day, and night where there is one), A to Z by city.
    static var bundledCredits: [PhotoCreditItem] {
        guard let manifest else { return legacyCredits }
        var seen = Set<String>()
        // Default scenes aren't any city's photo: not listed.
        return manifest.filter { $0.scene == nil }.flatMap { entry -> [PhotoCreditItem] in
            guard seen.insert(entry.key).inserted else { return [] }
            let city = entry.names.first ?? entry.key
            var items = [PhotoCreditItem(id: "b:" + entry.key, city: city, author: entry.credit?.author,
                                         license: entry.credit?.license,
                                         source: creditLink(entry.credit?.source),
                                         fallback: entry.file)]
            if let night = entry.night, night.file != nil || night.credit != nil {
                items.append(PhotoCreditItem(id: "b:" + entry.key + "-night", city: city + ", night",
                                             author: night.credit?.author, license: night.credit?.license,
                                             source: creditLink(night.credit?.source),
                                             fallback: night.file))
            }
            return items
        }
        .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    // MARK: Layout

    /// Where a photo's skyline sits when the manifest doesn't say (old manifests).
    static let defaultFocus = 0.62

    /// The card's "gap target": the point between the end of its name/time column and the start
    /// of its hour tiles (CityRow's layout: side padding, the label column, half the label gap),
    /// in points from the card's left edge, for a card `cardWidth` wide.
    static func gapTarget(cardWidth: CGFloat) -> CGFloat {
        let content = max(0, cardWidth - 2 * RowCard.sidePadding)
        return RowCard.sidePadding + Strip.labelWidth(content) + Strip.labelGap / 2
    }

    /// The photo's frame in a card of `box` (WidgetPhotoPlacement, as the widgets place it):
    /// scaled to cover the card, then slid across so the photo's landmark (`focusX`, 0…1 of its
    /// width; nil: its centre) lands on `targetX` (points from the card's left edge, the gap
    /// between its text and its tiles; nil: the card's centre), zoomed up to 15% beyond cover only
    /// when the photo's edge would otherwise stop the landmark short of it; moved up or down so the
    /// point `focus` of the way down the photo sits at the card's vertical centre, then down as far
    /// as needed to keep the landmark's tip (`top`, 0…1 of its height; nil: no rule) at least 8% of
    /// the card's height below its top edge. Always clamped so the photo covers the card.
    /// How much of a card's height an AI plate's landmark (tip to skyline) fills.
    static let cardLandmarkFill: CGFloat = 0.55

    static func photoRect(image: CGSize, in box: CGSize, focus: Double?, focusX: Double? = nil,
                          targetX: CGFloat? = nil, top: Double? = nil) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else {
            return CGRect(origin: .zero, size: box)
        }
        let fit = WidgetPhotoPlacement.place(imageWidth: image.width, imageHeight: image.height, in: box,
                                             focus: CGFloat(focus ?? defaultFocus),
                                             landmarkX: CGFloat(focusX ?? Double(WidgetPhotoPlacement.defaultLandmarkX)),
                                             targetX: targetX, top: top.map { CGFloat($0) },
                                             // An AI plate (measured landmark) fills 55% of the card's height.
                                             fill: focusX != nil ? cardLandmarkFill : nil)
        return CGRect(origin: fit.offset, size: fit.size)
    }

    // MARK: Shading

    /// The phase a photo is tinted for: none for a real night photo (shown as taken), else the
    /// time of day's (a day photo darkened at night only when the city has no night photo).
    static func tintPhase(_ phase: Sky.Phase, photo: SkylinePhoto) -> Sky.Phase {
        photo.night ? .day : phase
    }

    /// A day photo shaded for the time of day there: darker and cooler at night (only for a city
    /// without a night photo), warmer and a little darker in twilight, as it is by day.
    static func shade(_ phase: Sky.Phase) -> Color {
        switch phase {
        case .night: return Color(red: 0.400, green: 0.459, blue: 0.522)
        case .twilight: return Color(red: 0.941, green: 0.820, blue: 0.714)
        case .day: return .white
        }
    }

    static func saturation(_ phase: Sky.Phase) -> Double {
        switch phase {
        case .night: return 0.75
        case .twilight: return 1.1
        case .day: return 1
        }
    }

    /// The drawn skyline's sky, top to bottom.
    static func sky(_ phase: Sky.Phase) -> [Color] {
        switch phase {
        case .day: return [Theme.rgb(0x3D74B0), Theme.rgb(0x1C3A5E)]
        case .twilight: return [Theme.rgb(0x4F78A3), Theme.rgb(0x24384F)]
        case .night: return [Theme.rgb(0x141E3C), Theme.rgb(0x0A0E1C)]
        }
    }

    /// The drawn buildings' colour.
    static func ink(_ phase: Sky.Phase) -> Color {
        switch phase {
        case .day: return Theme.rgb(0x0A0E1C)
        case .twilight: return Theme.rgb(0x0A0E1C)
        case .night: return Color.black
        }
    }
}

/// What a downloaded plate's record holds: the city it is for (its metro's name), when it was
/// asked for, the image file (nil when there was none: not asked for again within 30 days), its
/// credit, and its hosted plate's key (plates-remote.json; nil only in records from before, which
/// are removed).
struct CityPhotoRecord: Codable {
    var name: String
    var fetched: Date
    var file: String?
    var credit: SkylinePhotoCredit?
    var plate: String? = nil
}

/// The hosted AI plates (RemotePlates) of the cards that show one: each plate, day and night,
/// downloaded once (the request is the image's URL alone: no cookies, no extra headers) and kept in
/// Caches under its key, so cities of the same metro share it; a plate that isn't there is not
/// asked for again within 30 days. Never blocks the UI; the card shows its default scene until the
/// plate is ready, and offline nothing changes.
@MainActor
final class CityPhotos: ObservableObject {
    static let shared = CityPhotos()

    nonisolated static let enabledKey = "downloadCityPhotos"
    nonisolated static let retryAfter: TimeInterval = 30 * 24 * 3600
    /// Set once the photos downloaded from Wikimedia before (and their records) have been removed.
    nonisolated static let cleanedKey = "cityPhotosWikimediaRemoved"

    /// Settings → Cities → Download City Photos (on unless turned off).
    nonisolated static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Loaded plates, by record name (`recordName`).
    @Published private(set) var images: [String: UIImage] = [:]
    /// What's on disk, by record name.
    @Published private(set) var records: [String: CityPhotoRecord] = [:]
    /// Plates (by key) being loaded.
    private var inFlight = Set<String>()
    /// Plates (by key) asked for (or failed offline) since launch: not again until the next launch.
    private var tried = Set<String>()
    private var recordsTask: Task<Void, Never>?

    private init() {
        recordsTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { () -> [String: CityPhotoRecord] in
                CityPhotos.removeWikimediaPhotos()
                // Read the index once off the main thread, before the first card resolves its photo.
                _ = RemotePlates.file
                return CityPhotos.readRecords()
            }.value
            guard let self else { return }
            for (name, record) in found where self.records[name] == nil { self.records[name] = record }
        }
    }

    /// A plate's record (and image file) name: "p-<key>-day" or "p-<key>-night".
    nonisolated static func recordName(_ key: String, night: Bool) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let safe = String(key.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return "p-" + safe + (night ? "-night" : "-day")
    }

    /// The card's hosted plate images, day and night, once both are loaded (nil, nil until then,
    /// or when the card shows no hosted plate): a plate is a pair, so one without its night image
    /// isn't shown (its default scene is), as on Android and the Mac.
    func plateImages(for place: Place) -> (day: UIImage?, night: UIImage?) {
        guard let key = SkylineArt.choice(for: place).hosted,
              let day = images[Self.recordName(key, night: false)],
              let night = images[Self.recordName(key, night: true)] else { return (nil, nil) }
        return (day, night)
    }

    /// Downloaded plates' credits (day and night), A to Z by city.
    var credits: [PhotoCreditItem] {
        records.compactMap { (name, record) -> PhotoCreditItem? in
            // Only plates the index still publishes: no card can show the others.
            guard record.file != nil, let key = record.plate, RemotePlates.byKey[key] != nil else { return nil }
            let city = name.hasSuffix("-night") ? record.name + ", night" : record.name
            return PhotoCreditItem(id: "p:" + name, city: city, author: record.credit?.author ?? RemotePlates.credit.author,
                                   license: record.credit?.license ?? RemotePlates.credit.license,
                                   source: nil, fallback: nil)
        }
        .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    /// Loads the card's hosted plate from disk, or downloads it (once), in the background: the day
    /// image, then the night one. Nothing for a card with a built-in photo or a default scene.
    func request(_ place: Place) {
        guard Self.enabled, let key = SkylineArt.choice(for: place).hosted else { return }
        guard images[Self.recordName(key, night: false)] == nil || images[Self.recordName(key, night: true)] == nil,
              !inFlight.contains(key), !tried.contains(key) else { return }
        inFlight.insert(key)
        Task { [weak self] in
            await self?.load(key)
        }
    }

    private func load(_ key: String) async {
        defer {
            inFlight.remove(key)
            tried.insert(key)
        }
        _ = await recordsTask?.value
        guard await loadImage(key, night: false) else { return }
        _ = await loadImage(key, night: true)
    }

    /// One plate image: loaded already, from disk when it was kept, else downloaded (a copy the
    /// system cleared is downloaded again). True when it is loaded.
    private func loadImage(_ key: String, night: Bool) async -> Bool {
        let name = Self.recordName(key, night: night)
        if images[name] != nil { return true }
        if let record = records[name] {
            if let file = record.file {
                if let image = await Self.readImage(file) {
                    images[name] = image
                    return true
                }
                // The system cleared the image: download it again.
            } else if Date().timeIntervalSince(record.fetched) < Self.retryAfter {
                return false
            }
        }
        guard Self.enabled, let url = RemotePlates.imageURL(key, night: night) else { return false }
        let city = RemotePlates.byKey[key]?.name ?? key
        switch await Self.fetch(url) {
        case .offline:
            return false
        case .photo(let data):
            if let image = await Self.decode(data) {
                let record = CityPhotoRecord(name: city, fetched: Date(), file: name + ".jpg",
                                             credit: RemotePlates.credit, plate: key)
                await Self.write(record, name: name, data: data)
                records[name] = record
                images[name] = image
                return true
            }
        case .missing:
            break
        }
        // Not there (or not an image): not asked for again within 30 days.
        let record = CityPhotoRecord(name: city, fetched: Date(), file: nil, credit: nil, plate: key)
        records[name] = record
        await Self.write(record, name: name, data: nil)
        return false
    }

    // MARK: Disk

    nonisolated private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("CityPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Once: removes the photos downloaded from Wikimedia before (and their records), and moves
    /// the hosted plates downloaded before that the index still publishes to their key's name ("p-<key>-day").
    nonisolated private static func removeWikimediaPhotos() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: cleanedKey), let dir = directory() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var kept = Set<String>()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(CityPhotoRecord.self, from: data),
                  let key = record.plate, RemotePlates.byKey[key] != nil, let image = record.file else { continue }
            let old = file.deletingPathExtension().lastPathComponent
            let name = recordName(key, night: old.hasSuffix(".night") || old.hasSuffix("-night"))
            guard !kept.contains(name) else { continue }
            if image != name + ".jpg" {
                let target = dir.appendingPathComponent(name + ".jpg")
                if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                guard (try? fm.moveItem(at: dir.appendingPathComponent(image), to: target)) != nil else { continue }
            }
            let moved = CityPhotoRecord(name: RemotePlates.byKey[key]?.name ?? record.name, fetched: record.fetched,
                                        file: name + ".jpg", credit: RemotePlates.credit, plate: key)
            guard let json = try? encoder.encode(moved),
                  (try? json.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)) != nil
            else { continue }
            kept.insert(name)
        }
        // Everything else: Wikimedia photos, their records, and plates' old records and misses.
        for file in files where !kept.contains(file.deletingPathExtension().lastPathComponent) {
            try? fm.removeItem(at: file)
        }
        defaults.set(true, forKey: cleanedKey)
    }

    nonisolated private static func readRecords() -> [String: CityPhotoRecord] {
        guard let dir = directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [:] }
        var out: [String: CityPhotoRecord] = [:]
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let record = try? decoder.decode(CityPhotoRecord.self, from: data),
               record.plate != nil {
                out[file.deletingPathExtension().lastPathComponent] = record
            }
        }
        return out
    }

    nonisolated private static func readImage(_ file: String) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            guard let dir = directory(),
                  let image = UIImage(contentsOfFile: dir.appendingPathComponent(file).path) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }

    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            guard let image = UIImage(data: data), image.size.width > 0 else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }

    nonisolated private static func write(_ record: CityPhotoRecord, name: String, data: Data?) async {
        await Task.detached(priority: .utility) {
            guard let dir = directory() else { return }
            if let data, let file = record.file {
                try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
            }
            if let json = try? JSONEncoder().encode(record) {
                try? json.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
            }
        }.value
    }

    // MARK: Network

    private enum Fetch {
        case photo(Data)
        /// Not there: the default scene stays (asked again in 30 days).
        case missing
        /// Offline, or the server was busy: try again next launch.
        case offline
    }

    /// A failure worth asking again about on the next launch (no connection, timeout, rate limit,
    /// server trouble); any other client error is recorded like a plate that isn't there.
    nonisolated private static func transient(_ status: Int) -> Bool {
        status == 0 || status == 408 || status == 429 || status >= 500
    }

    /// The plates' requests: no cookies, no cache, no stored credentials, and nothing added to the
    /// request but its URL.
    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// One plate image: its JPEG, `.missing` when it isn't there, `.offline` to ask again next launch.
    nonisolated private static func fetch(_ url: URL) async -> Fetch {
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, !data.isEmpty else { return transient(status) ? .offline : .missing }
            return .photo(data)
        } catch {
            return .offline
        }
    }
}

/// Small copies of the cards' photos for the widgets, which can't read the app's asset catalog or
/// Caches: one ~600×300 JPEG per city on the list in the App Group container (Skylines/<slug>.jpg)
/// and Skylines/index.json naming each city's file (see WidgetSkylines). A city with a night photo
/// also gets Skylines/<slug>-night.jpg, named in its entry's `night` and indexed under
/// "<id>|night" (with where it came from, so it too is rewritten only when it changes); the
/// widgets show it after dark. Rewritten only when a city's photo changes; the widgets reload
/// when anything did.
@MainActor
enum WidgetPhotoExport {
    private struct Job {
        let id: String
        let entry: WidgetSkylines.Entry
        let image: UIImage
    }

    /// A city's night photo's key in the index.
    nonisolated static func nightID(_ id: String) -> String { id + "|night" }

    /// A short, stable name for an id (FNV-1a, 32 bits, hex), for a second card's file names.
    nonisolated static func shortHash(_ id: String) -> String {
        var h: UInt32 = 2166136261
        for byte in id.utf8 { h = (h ^ UInt32(byte)) &* 16777619 }
        return String(h, radix: 16)
    }

    /// skylines.json's "focus" (how far down the photo its skyline band sits, 0…1), "focusX"
    /// (where across it its landmark stands, 0…1; v3) and "top" (how far down it the landmark's
    /// tip sits, 0…1; optional) by photo id: "b:<key>" for a day photo, "b:<key>-night" for a night
    /// one. Downloaded photos have none.
    nonisolated private static let bundledPlacement: (focus: [String: Double], focusX: [String: Double],
                                                      top: [String: Double]) = {
        struct Night: Decodable {
            var focus: Double?
            var focusX: Double?
            var top: Double?
        }
        struct Item: Decodable {
            var key: String?
            var focus: Double?
            var focusX: Double?
            var top: Double?
            var night: Night?
        }
        guard let list = SkylineManifestFile<Item>.bundled() else { return ([:], [:], [:]) }
        var focus: [String: Double] = [:], focusX: [String: Double] = [:], top: [String: Double] = [:]
        for item in list {
            guard let key = item.key else { continue }
            let day = "b:" + key, night = "b:" + key + "-night"
            if focus[day] == nil, let f = SkylineManifestEntry.unitFocus(item.focus) { focus[day] = f }
            if focusX[day] == nil, let f = SkylineManifestEntry.unitFocus(item.focusX) { focusX[day] = f }
            if top[day] == nil, let f = SkylineManifestEntry.unitFocus(item.top) { top[day] = f }
            if focus[night] == nil, let f = SkylineManifestEntry.unitFocus(item.night?.focus) { focus[night] = f }
            if focusX[night] == nil, let f = SkylineManifestEntry.unitFocus(item.night?.focusX) { focusX[night] = f }
            if top[night] == nil, let f = SkylineManifestEntry.unitFocus(item.night?.top) { top[night] = f }
        }
        return (focus, focusX, top)
    }()

    /// The bundled (or hosted AI plate's, "p:<key>") photo's skyline focus for a SkylinePhoto id,
    /// or nil (not measured).
    nonisolated static func focus(forID id: String) -> Double? {
        bundledPlacement.focus[id] ?? RemotePlates.placement(forID: id)?.focus
    }

    /// The bundled (or hosted AI plate's) photo's landmark across it for a SkylinePhoto id, or nil
    /// (v2).
    nonisolated static func focusX(forID id: String) -> Double? {
        bundledPlacement.focusX[id] ?? RemotePlates.placement(forID: id)?.focusX
    }

    /// The bundled (or hosted AI plate's) photo's landmark tip down it for a SkylinePhoto id, or
    /// nil (none).
    nonisolated static func top(forID id: String) -> Double? {
        bundledPlacement.top[id] ?? RemotePlates.placement(forID: id)?.top
    }

    /// The copy written for a photo of `size`: 300 pt tall, its own width kept between 2:1 and 3:1
    /// (a 3:1 city plate whole at 900×300; a wider photo cropped to 3:1, a narrower one to 2:1,
    /// each from its centre), and where the scaled photo is drawn in it.
    nonisolated static func exportGeometry(_ size: CGSize) -> (canvas: CGSize, drawn: CGRect) {
        let height: CGFloat = 300
        guard size.width > 0, size.height > 0 else {
            return (CGSize(width: 2 * height, height: height), CGRect(x: 0, y: 0, width: 2 * height, height: height))
        }
        let aspect = min(max(size.width / size.height, 2), 3)
        let canvas = CGSize(width: (height * aspect).rounded(), height: height)
        let scale = max(canvas.width / size.width, canvas.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return (canvas, CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h))
    }

    /// A photo's focus or top (`vertical`) or focusX, 0…1 of the photo, as the same fraction of the
    /// copy written for it (moved by any crop), or nil when unknown.
    nonisolated static func exportFraction(_ value: Double?, size: CGSize, vertical: Bool) -> Double? {
        guard let value, value.isFinite else { return nil }
        let g = exportGeometry(size)
        let point = vertical ? g.drawn.minY + CGFloat(value) * g.drawn.height : g.drawn.minX + CGFloat(value) * g.drawn.width
        let span = vertical ? g.canvas.height : g.canvas.width
        guard span > 0 else { return nil }
        return Double(min(max(point / span, 0), 1))
    }

    /// A photo's index entry: its file, where it came from, its focus, landmark and landmark tip
    /// mapped into the written copy (a photo with none gets the landmark at its centre, which
    /// stays there, and no tip rule), and the copy's format.
    private static func entry(file: String, photo: SkylinePhoto) -> WidgetSkylines.Entry {
        let size = photo.image.size
        return WidgetSkylines.Entry(file: file, source: photo.id,
                                    focus: exportFraction(focus(forID: photo.id), size: size, vertical: true),
                                    focusX: exportFraction(focusX(forID: photo.id), size: size, vertical: false),
                                    top: exportFraction(top(forID: photo.id), size: size, vertical: true),
                                    format: WidgetSkylines.exportFormat)
    }

    private static var task: Task<Void, Never>?
    /// The cities the large widget shows, whose hosted plates are asked for even off screen.
    private static let widgetCities = 5

    static func sync(_ places: [Place], downloads: Bool) {
        // Screenshot mode never writes to the shared folder: the in-app widget previews read the
        // bundled photos straight from the app instead.
        if Screenshots.isActive {
            WidgetSkylines.inAppImage = { c in
                SkylineArt.photo(for: Place(name: c.name, timeZoneID: c.timeZoneID))?.image.cgImage
            }
            WidgetSkylines.inAppNightImage = { c in
                SkylineArt.nightPhoto(for: Place(name: c.name, timeZoneID: c.timeZoneID))?.image.cgImage
            }
            WidgetSkylines.inAppFocus = { c, night in
                let place = Place(name: c.name, timeZoneID: c.timeZoneID)
                let shown = night ? SkylineArt.nightPhoto(for: place) : SkylineArt.photo(for: place)
                return shown.flatMap { WidgetPhotoExport.focus(forID: $0.id) }
            }
            WidgetSkylines.inAppFocusX = { c, night in
                let place = Place(name: c.name, timeZoneID: c.timeZoneID)
                let shown = night ? SkylineArt.nightPhoto(for: place) : SkylineArt.photo(for: place)
                return shown.flatMap { WidgetPhotoExport.focusX(forID: $0.id) }
            }
            WidgetSkylines.inAppTop = { c, night in
                let place = Place(name: c.name, timeZoneID: c.timeZoneID)
                let shown = night ? SkylineArt.nightPhoto(for: place) : SkylineArt.photo(for: place)
                return shown.flatMap { WidgetPhotoExport.top(forID: $0.id) }
            }
            return
        }
        guard let dir = WidgetSkylines.directory else { return }
        var jobs: [Job] = []
        var ids = Set<String>()
        // Cities whose hosted plate hasn't loaded yet: a copy of it written before is kept meanwhile
        // (else their default scene is written).
        // By widget id: the hosted plate's key the city waits for.
        var waiting: [String: String] = [:]
        // The first card of each name and zone is indexed under that too (WidgetSkylines.id), for
        // widget-chosen cities: by plain id, its photo id.
        var aliases: [String: String] = [:]
        var slugs = Set<String>()
        for (i, place) in places.enumerated() {
            // By everything the photo is chosen by, so two cards of one name and zone in different
            // places each get their own photo.
            let id = WidgetSkylines.photoID(name: place.name, timeZoneID: place.timeZoneID,
                                            countryCode: place.countryCode, latitude: place.latitude,
                                            longitude: place.longitude)
            guard ids.insert(id).inserted else { continue }
            let plain = WidgetSkylines.id(name: place.name, timeZoneID: place.timeZoneID)
            if plain != id, aliases[plain] == nil { aliases[plain] = id }
            if downloads && i < widgetCities { CityPhotos.shared.request(place) }
            // A hosted AI plate is exported as a built-in one is: with its focus, landmark and tip.
            // Downloads off: the default scene.
            let plates: (day: UIImage?, night: UIImage?) = downloads ? CityPhotos.shared.plateImages(for: place) : (nil, nil)
            if downloads, plates.day == nil, let key = SkylineArt.choice(for: place).hosted { waiting[id] = key }
            guard let photo = SkylineArt.photo(for: place, plate: plates.day) else { continue }
            // Its files' name: the city and zone, made unique for a second card of the same.
            var slug = SkylineArt.slug(for: place)
            if slugs.contains(slug) { slug += "_" + Self.shortHash(id) }
            slugs.insert(slug)
            let night = SkylineArt.nightPhoto(for: place, plate: plates.day, plateNight: plates.night)
            var entry = Self.entry(file: slug + ".jpg", photo: photo)
            if let night {
                entry.night = slug + "-night.jpg"
                jobs.append(Job(id: nightID(id), entry: Self.entry(file: slug + "-night.jpg", photo: night),
                                image: night.image))
            }
            jobs.append(Job(id: id, entry: entry, image: photo.image))
        }
        let previous = task
        previous?.cancel()
        task = Task.detached(priority: .utility) {
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            if write(jobs, waiting: waiting, aliases: aliases, dir: dir) {
                await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }

    /// Writes the photos that changed and the index; removes photos no city uses. True if anything changed.
    /// Cities in `waiting` keep their earlier copy of their current hosted plate (that key's, not
    /// another's) until it has loaded. `aliases` (plain id -> photo id) index a card's entries under
    /// its name and zone too, unless a card has exactly that id.
    nonisolated private static func write(_ jobs: [Job], waiting: [String: String], aliases: [String: String],
                                          dir: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = WidgetSkylines.readIndex()
        var index: [String: WidgetSkylines.Entry] = [:]
        var changed = false
        func plateCopy(_ id: String, source: String) -> WidgetSkylines.Entry? {
            guard let entry = old[id], entry.source == source,
                  fm.fileExists(atPath: dir.appendingPathComponent(entry.file).path) else { return nil }
            return entry
        }
        var kept = Set<String>()
        for (id, key) in waiting {
            guard var entry = plateCopy(id, source: "p:" + key) else { continue }
            if let night = plateCopy(nightID(id), source: "p:" + key + "-night"), entry.night == night.file {
                index[nightID(id)] = night
            } else {
                entry.night = nil
            }
            index[id] = entry
            kept.insert(id)
        }
        // Night photos first, so a city's entry names its night file only once that file is written.
        for job in jobs.sorted(by: { $0.id.hasSuffix("|night") && !$1.id.hasSuffix("|night") }) {
            let city = job.id.hasSuffix("|night") ? String(job.id.dropLast(6)) : job.id
            if kept.contains(city) { continue }
            let url = dir.appendingPathComponent(job.entry.file)
            var entry = job.entry
            if entry.night != nil, index[nightID(job.id)] == nil { entry.night = nil }
            // The same photo already there (its entry may still change, by its night file).
            // A copy in an older format (cropped to 600×300) is written again.
            if let previous = old[job.id], previous.file == entry.file, previous.source == entry.source,
               previous.format == entry.format, fm.fileExists(atPath: url.path) {
                index[job.id] = entry
                continue
            }
            guard let data = jpeg(job.image) else { continue }
            if (try? data.write(to: url, options: .atomic)) != nil {
                index[job.id] = entry
                changed = true
            }
        }
        for (plain, id) in aliases where index[plain] == nil {
            guard let entry = index[id] else { continue }
            index[plain] = entry
            if let night = index[nightID(id)] { index[nightID(plain)] = night }
        }
        if index != old {
            changed = true
            if let json = try? JSONEncoder().encode(index), let url = WidgetSkylines.indexURL {
                try? json.write(to: url, options: .atomic)
            }
        }
        // Photos no city on the list uses any more.
        let keep = Set(index.values.map(\.file))
        if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
            for file in files where file.hasSuffix(".jpg") && !keep.contains(file) {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
            }
        }
        return changed
    }

    /// The photo filling its copy (exportGeometry: 300 tall, 2:1 to 3:1, a 3:1 city plate whole at
    /// 900×300, so the widget can place its landmark itself), JPEG at 0.6.
    nonisolated private static func jpeg(_ image: UIImage) -> Data? {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return nil }
        let geometry = exportGeometry(image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: geometry.canvas, format: format).jpegData(withCompressionQuality: 0.6) { _ in
            image.draw(in: geometry.drawn)
        }
    }
}

/// The card's background: the city's photo filling it (its night photo after dark, shown as
/// taken; a day photo shaded for the time of day there), or a skyline drawn for it on that time of
/// day's sky. Day and night photos crossfade when the phase changes.
struct SkylineBackdrop: View {
    let seed: String
    let photo: SkylinePhoto?
    let phase: Sky.Phase
    /// Where the photo's landmark goes, in points from the card's left edge (the gap between the
    /// card's text and its tiles: SkylineArt.gapTarget); nil: the card's centre.
    var targetX: CGFloat? = nil

    var body: some View {
        Color.clear
            .overlay { GeometryReader { proxy in ZStack { art(proxy.size) } } }
            .clipped()
            .animation(.easeInOut(duration: 0.6), value: phase)
            .animation(.easeInOut(duration: 0.6), value: photo?.id)
    }

    @ViewBuilder private func art(_ size: CGSize) -> some View {
        if let photo {
            let tint = SkylineArt.tintPhase(phase, photo: photo)
            // Filling the card, its skyline band (the photo's focus) at the card's centre and its
            // landmark (focusX) on the gap between the text and the tiles.
            let rect = SkylineArt.photoRect(image: photo.image.size, in: size, focus: photo.focus,
                                            focusX: photo.focusX, targetX: targetX, top: photo.top)
            Image(uiImage: photo.image)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .frame(width: size.width, height: size.height)
                .saturation(SkylineArt.saturation(tint))
                .colorMultiply(SkylineArt.shade(tint))
                .id(photo.id)
                .transition(.opacity)
        } else {
            DrawnSkyline(seed: seed, phase: phase)
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        }
    }
}

/// The same "random" numbers every time for the same city name, so its drawn skyline stays put.
struct SeededRandom {
    private var x: UInt32

    init(_ seed: String) {
        var v: UInt32 = 0
        for u in seed.unicodeScalars { v = v &* 31 &+ UInt32(truncatingIfNeeded: u.value) }
        x = v
    }

    mutating func next() -> CGFloat {
        x = x &* 1_664_525 &+ 1_013_904_223
        return CGFloat(x) / 4_294_967_296
    }
}

/// A skyline drawn in code: buildings of the city's own (seeded) heights, lit windows after dark,
/// the sun or moon, on the sky for the time of day.
struct DrawnSkyline: View {
    let seed: String
    let phase: Sky.Phase

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let sky = SkylineArt.sky(phase)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // The sun, or the moon, or the setting sun low on the horizon.
        let glowCenter: CGPoint
        let glowRadius: CGFloat
        let glowColor: Color
        switch phase {
        case .night:
            glowCenter = CGPoint(x: w * 0.86, y: h * 0.28); glowRadius = 9; glowColor = Theme.moon.opacity(0.9)
        case .twilight:
            glowCenter = CGPoint(x: w * 0.88, y: h * 0.82); glowRadius = 22; glowColor = Theme.rgb(0xF39A72).opacity(0.85)
        case .day:
            glowCenter = CGPoint(x: w * 0.86, y: h * 0.25); glowRadius = 12; glowColor = Color.white.opacity(0.95)
        }
        let halo = glowRadius * 2.2
        context.fill(Path(ellipseIn: CGRect(x: glowCenter.x - halo, y: glowCenter.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [glowColor.opacity(0.35), glowColor.opacity(0)]),
                                           center: glowCenter, startRadius: glowRadius, endRadius: halo))
        context.fill(Path(ellipseIn: CGRect(x: glowCenter.x - glowRadius, y: glowCenter.y - glowRadius,
                                            width: glowRadius * 2, height: glowRadius * 2)),
                     with: .color(glowColor))

        // Windows draw from their own generator so the buildings never change with the phase.
        var lights = SeededRandom(seed + "|windows")
        let ink = SkylineArt.ink(phase)
        let windowChance: CGFloat = phase == .night ? 0.35 : (phase == .twilight ? 0.18 : 0)
        let layout = Self.layout(seed: seed, size: size)

        // The front row of buildings, and their lit windows.
        var front = Path()
        var windows = Path()
        for rect in layout.front {
            front.addRect(rect)
            if windowChance > 0 {
                var y = rect.minY + 4
                while y < h - 3 {
                    var wx = rect.minX + 2
                    while wx < rect.maxX - 2 {
                        if lights.next() < windowChance { windows.addRect(CGRect(x: wx, y: y, width: 1.6, height: 2)) }
                        wx += 4
                    }
                    y += 5
                }
            }
        }

        // A paler row behind.
        var back = Path()
        for rect in layout.back { back.addRect(rect) }

        context.fill(back, with: .color(ink.opacity(0.55)))
        context.fill(front, with: .color(ink))
        context.fill(windows, with: .color(Theme.sun.opacity(0.8)))
    }

    /// The buildings for a city's seed at a size: the front row left to right, and the paler row
    /// behind. The same every time for the same seed and size.
    static func layout(seed: String, size: CGSize) -> (front: [CGRect], back: [CGRect]) {
        let w = size.width, h = size.height
        var random = SeededRandom(seed)
        var front: [CGRect] = []
        var x: CGFloat = 0
        while x < w {
            let bw = 8 + random.next() * 18
            let bh = h * (0.18 + random.next() * 0.42)
            front.append(CGRect(x: x, y: h - bh, width: bw, height: bh))
            x += 6 + random.next() * 14
        }
        var back: [CGRect] = []
        let backCount = max(12, Int(w / 12))
        for _ in 0..<backCount {
            let bx = random.next() * w
            let bw = 10 + random.next() * 22
            let bh = h * (0.25 + random.next() * 0.35)
            back.append(CGRect(x: bx, y: h - bh, width: bw, height: bh))
        }
        return (front, back)
    }
}

/// Whether the card is bright or dark behind the time (the area the time actually covers, as the
/// card shades it for the time of day there and darkens it with its scrim): dark digits outlined
/// in white go on a bright area, white digits outlined in black on a dark one.
enum BannerInk {
    /// Brighter than this (relative luminance, 0 to 1) takes dark digits.
    static let threshold: Double = 0.40

    /// Recent answers, by photo (or drawn city and size), phase and area, so scrubbing stays fast.
    private static var cache: [String: Bool] = [:]

    /// `region` is the area behind the time in the card's unit square (0...1 each way, top-left
    /// origin); `size` is the card's; `targetX` where the photo's landmark goes (as SkylineBackdrop).
    static func isBright(photo: SkylinePhoto?, seed: String, phase: Sky.Phase, size: CGSize, region: CGRect,
                         targetX: CGFloat? = nil) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        let area = region.isNull ? CGRect.zero : region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !area.isNull, area.width > 0.001, area.height > 0.001 else { return false }
        // A twentieth of the card is close enough for the area, a quarter for a photo's shape.
        func q(_ v: CGFloat) -> Int { Int((v * 20).rounded()) }
        let areaKey = "\(q(area.minX)),\(q(area.minY)),\(q(area.width)),\(q(area.height))"
        let key: String
        if let photo {
            let aspect = (size.width / size.height * 4).rounded() / 4
            let target = targetX.map { "\(q($0 / size.width))" } ?? "c"
            key = "photo|\(photo.id)|\(phase)|\(aspect)|\(target)|\(areaKey)"
        } else {
            key = "drawn|\(seed)|\(phase)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))|\(areaKey)"
        }
        if let hit = cache[key] { return hit }
        if cache.count > 300 { cache.removeAll() }

        let luminance: Double?
        if let photo {
            luminance = photoLuminance(photo.image, focus: photo.focus, focusX: photo.focusX, top: photo.top, targetX: targetX,
                                       phase: SkylineArt.tintPhase(phase, photo: photo), size: size, region: area)
        } else {
            luminance = drawnLuminance(seed: seed, phase: phase, size: size, region: area)
        }
        let bright = (luminance ?? 0) > threshold
        cache[key] = bright
        return bright
    }

    // MARK: Colour

    /// sRGB (0...1) to linear light.
    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance of an sRGB colour (0...1 components).
    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    // MARK: Photos

    /// The photo's area behind the time, as the card crops it (SkylineArt.photoRect: filling it,
    /// its focus at the card's centre, its landmark on `targetX`), drawn into a small bitmap, then
    /// saturated and tinted as the card shades it, darkened by the scrim, and averaged.
    private static func photoLuminance(_ photo: UIImage, focus: Double?, focusX: Double?, top: Double?, targetX: CGFloat?,
                                       phase: Sky.Phase, size: CGSize, region: CGRect) -> Double? {
        guard let cg = photo.cgImage else { return nil }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        guard iw > 0, ih > 0 else { return nil }
        // The card's frame in the photo's pixels (the inverse of the photo's frame in the card).
        let rect = SkylineArt.photoRect(image: CGSize(width: iw, height: ih), in: size, focus: focus,
                                        focusX: focusX, targetX: targetX, top: top)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let s = rect.width / iw
        let visible = CGRect(x: -rect.minX / s, y: -rect.minY / s, width: size.width / s, height: size.height / s)
        // Image rows run top to bottom, as the card's unit square does.
        let crop = CGRect(x: visible.minX + visible.width * region.minX, y: visible.minY + visible.height * region.minY,
                          width: visible.width * region.width, height: visible.height * region.height).integral
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard !crop.isNull, !crop.isEmpty, let part = cg.cropping(to: crop) else { return nil }

        let w = 24, h = 12
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        let saturation = SkylineArt.saturation(phase)
        let tint = components(SkylineArt.shade(phase))
        var total = 0.0
        for row in 0..<h {
            let v = Double(region.minY) + Double(region.height) * (Double(row) + 0.5) / Double(h)
            for col in 0..<w {
                let i = row * w + col
                let u = Double(region.minX) + Double(region.width) * (Double(col) + 0.5) / Double(w)
                let a = Double(px[i * 4 + 3]) / 255
                guard a > 0 else { continue }
                var r = Double(px[i * 4]) / 255 / a
                var g = Double(px[i * 4 + 1]) / 255 / a
                var b = Double(px[i * 4 + 2]) / 255 / a
                // .saturation: towards (or away from) the pixel's grey.
                let grey = 0.2126 * r + 0.7152 * g + 0.0722 * b
                r = min(max(grey + (r - grey) * saturation, 0), 1)
                g = min(max(grey + (g - grey) * saturation, 0), 1)
                b = min(max(grey + (b - grey) * saturation, 0), 1)
                // .colorMultiply (the time of day's tint), then the scrim over it.
                let k = CardScrim.remaining(u: u, v: v)
                total += luminance(r * tint.r * k, g * tint.g * k, b * tint.b * k)
            }
        }
        return total / Double(w * h)
    }

    // MARK: Drawn skylines

    /// The drawn skyline's area behind the time, sampled on a small grid: its buildings in their
    /// ink, the paler row behind at 55% over the sky, and the sky's gradient elsewhere, darkened
    /// by the scrim.
    private static func drawnLuminance(seed: String, phase: Sky.Phase, size: CGSize, region: CGRect) -> Double {
        let layout = DrawnSkyline.layout(seed: seed, size: size)
        let sky = SkylineArt.sky(phase).map { components($0) }
        let ink = components(SkylineArt.ink(phase))
        let top = sky.first ?? (r: 0, g: 0, b: 0, a: 1)
        let bottom = sky.last ?? top
        let cols = 24, rows = 12
        var total = 0.0
        for row in 0..<rows {
            let t = Double(region.minY) + Double(region.height) * (Double(row) + 0.5) / Double(rows)
            let y = size.height * CGFloat(t)
            let sr = top.r + (bottom.r - top.r) * t
            let sg = top.g + (bottom.g - top.g) * t
            let sb = top.b + (bottom.b - top.b) * t
            for col in 0..<cols {
                let u = Double(region.minX) + Double(region.width) * (Double(col) + 0.5) / Double(cols)
                let p = CGPoint(x: size.width * CGFloat(u), y: y)
                let k = CardScrim.remaining(u: u, v: t)
                if layout.front.contains(where: { $0.contains(p) }) {
                    total += luminance(ink.r * k, ink.g * k, ink.b * k)
                } else if layout.back.contains(where: { $0.contains(p) }) {
                    total += luminance((sr + (ink.r - sr) * 0.55) * k, (sg + (ink.g - sg) * 0.55) * k,
                                       (sb + (ink.b - sb) * 0.55) * k)
                } else {
                    total += luminance(sr * k, sg * k, sb * k)
                }
            }
        }
        return total / Double(cols * rows)
    }
}

/// The card's scrim, so the text along its bottom reads on any sky (day photos included): black at
/// 60% along the bottom edge, easing out (smoothstep) by 70% of the way up, and one from the left
/// behind the text column (50%, held at full strength to 34% across, past the longest names,
/// still 46% at the label column's edge, then easing out by 78%). Both fades are eased at each
/// end, so there is no visible edge where they start or stop. The only layer that darkens a photo
/// for its text, the same at every time of day; `remaining` and the drawn stops come from the same
/// curve, so the measured ink matches.
struct CardScrim: View {
    static let bottomOpacity = 0.6
    static let bottomReach = 0.70
    static let leftOpacity = 0.5
    static let leftHold = 0.34
    static let leftReach = 0.78
    /// Stops per fade: enough that the drawn ramp follows the smooth curve with no visible kink.
    private static let steps = 16

    /// Smoothstep on 0...1 (flat at both ends).
    static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// The bottom scrim's opacity at a distance `d` up from the bottom edge (unit height).
    static func upOpacity(_ d: Double) -> Double {
        bottomOpacity * (1 - ease(d / bottomReach))
    }

    /// The left scrim's opacity at `u` across (unit width).
    static func acrossOpacity(_ u: Double) -> Double {
        leftOpacity * (1 - ease((u - leftHold) / (leftReach - leftHold)))
    }

    /// How much of the photo shows through at a point of the card's unit square (top-left origin).
    static func remaining(u: Double, v: Double) -> Double {
        (1 - upOpacity(1 - v)) * (1 - acrossOpacity(u))
    }

    private static var bottomStops: [Gradient.Stop] {
        (0...steps).map { i -> Gradient.Stop in
            let location = bottomReach * Double(i) / Double(steps)
            return Gradient.Stop(color: Color.black.opacity(upOpacity(location)), location: location)
        }
    }

    private static var leftStops: [Gradient.Stop] {
        let ramp = (0...steps).map { i -> Gradient.Stop in
            let location = leftHold + (leftReach - leftHold) * Double(i) / Double(steps)
            return Gradient.Stop(color: Color.black.opacity(acrossOpacity(location)), location: location)
        }
        return [Gradient.Stop(color: Color.black.opacity(leftOpacity), location: 0)] + ramp
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: Self.bottomStops, startPoint: .bottom, endPoint: .top)
            LinearGradient(stops: Self.leftStops, startPoint: .leading, endPoint: .trailing)
        }
        .allowsHitTesting(false)
    }
}

/// The city's time on its banner: semibold digits with AM or PM small after them, on the scrim,
/// with a thin outline and a soft shadow. White outlined in black on a dark corner; on a bright
/// one, near-black outlined in white with a soft white glow.
struct BannerClock: View {
    let moment: Date
    let zone: TimeZone
    let use24h: Bool
    let size: CGFloat
    var bright = false

    /// The eight directions the outline's copies sit in, around the fill.
    private static let directions: [CGSize] = {
        let d = CGFloat(0.5.squareRoot())
        return [CGSize(width: -1, height: 0), CGSize(width: 1, height: 0),
                CGSize(width: 0, height: -1), CGSize(width: 0, height: 1),
                CGSize(width: -d, height: -d), CGSize(width: d, height: -d),
                CGSize(width: -d, height: d), CGSize(width: d, height: d)]
    }()

    private var fillColor: Color { bright ? Theme.bannerInk : .white }

    var body: some View {
        let parts = clockParts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // The digits' outline is 1 pt at 24 pt, 1.5 pt at 36 pt; AM/PM's is scaled to its own size.
            outlined(digitsText(parts.digits), width: size / 24)
            if let suffix = parts.suffix {
                outlined(suffixText(suffix), width: suffixSize / 24)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.numericText())
        .compositingGroup()
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.45 : 0.35), radius: 4, x: 0, y: 0)
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.3 : 0.25), radius: 1, x: 0, y: bright ? 0 : 1)
        .animation(.easeInOut(duration: 0.6), value: bright)
    }

    /// The text with an outline under its fill: copies nudged out on every side, drawn opaque
    /// and flattened, so the outline's opacity is applied once rather than stacking up.
    private func outlined(_ t: Text, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<Self.directions.count, id: \.self) { i in
                    t.offset(x: Self.directions[i].width * width, y: Self.directions[i].height * width)
                }
            }
            .foregroundStyle(bright ? Color.white : Color.black)
            .compositingGroup()
            .opacity(bright ? 0.85 : 0.6)
            .accessibilityHidden(true)
            t.foregroundStyle(fillColor)
        }
    }

    private var clockParts: (digits: String, suffix: String?) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let p = cal.dateComponents([.hour, .minute], from: moment)
        return ClockText.parts(hour: p.hour ?? 0, minute: p.minute ?? 0, use24h: use24h)
    }

    private func digitsText(_ digits: String) -> Text {
        Text(digits)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .tracking(-0.02 * size)
    }

    /// AM/PM: never under 13 pt, so it reads on compact cards too.
    private var suffixSize: CGFloat { max(13, size * 0.45) }

    private func suffixText(_ suffix: String) -> Text {
        Text("\u{2009}" + suffix).font(.system(size: suffixSize, weight: .semibold)).tracking(0.3)
    }
}

/// Where a city is in its working week at a moment: working (until when), or off hours, the
/// weekend, a day off or a public holiday (and when work starts again).
struct WorkStatus {
    enum Kind { case working, offHours, weekend, dayOff, holiday }

    let kind: Kind
    /// "Working", "Off hours", "Weekend", "Day off", or the holiday's name.
    let title: String
    /// "until 6 PM", "back 9 AM Mon"; nil when not asked for or not found within 8 days.
    let detail: String?

    var color: Color {
        switch kind {
        case .working: return Theme.rgb(0x9AD3A8)
        case .offHours: return Theme.rgb(0xD9DEE6)
        case .weekend, .dayOff: return Theme.rgb(0xF2C66D)
        case .holiday: return Theme.rgb(0xF39A72)
        }
    }

    var symbol: String {
        switch kind {
        case .working: return "briefcase.fill"
        case .offHours: return "moon.fill"
        case .weekend: return "sun.max.fill"
        case .dayOff: return "calendar"
        case .holiday: return "star.fill"
        }
    }

    /// "Working, until 6 PM", for VoiceOver.
    var spoken: String { [title, detail].compactMap { $0 }.joined(separator: ", ") }

    static func of(_ place: Place, at moment: Date, start: Int, end: Int, use24h: Bool, withDetail: Bool) -> WorkStatus {
        let working = WorkWeek.isWorking(place, at: moment, start: start, end: end)
        let kind: Kind
        let title: String
        if working {
            kind = .working; title = "Working"
        } else {
            let off = WorkWeek.offLabel(place, at: moment, start: start, end: end) ?? "Off hours"
            switch off {
            case "Off hours": kind = .offHours
            case "Weekend": kind = .weekend
            case "Day off": kind = .dayOff
            default: kind = .holiday
            }
            title = off
        }
        guard withDetail, let change = nextChange(place, from: moment, working: working, start: start, end: end) else {
            return WorkStatus(kind: kind, title: title, detail: nil)
        }
        let cal = place.calendar
        let parts = cal.dateComponents([.hour, .minute], from: change)
        var text = WorkWeek.clock(Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60, use24h: use24h)
        if !cal.isDate(change, inSameDayAs: moment) { text += " " + TimeMath.weekday(change, in: place.timeZone) }
        return WorkStatus(kind: kind, title: title, detail: (working ? "until " : "back ") + text)
    }

    /// Recent answers, so scrubbing and redrawing don't scan the week again.
    private static var cache: [String: Date?] = [:]

    /// The first quarter-hour after the moment when the city stops (or starts) working, looking up
    /// to 8 days ahead: hour by hour, then quarter-hour by quarter-hour within the hour it changes.
    static func nextChange(_ place: Place, from moment: Date, working: Bool, start: Int, end: Int) -> Date? {
        let base = Date(timeIntervalSinceReferenceDate: (moment.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
        let days = place.workDays.map { $0.sorted().map(String.init).joined(separator: ",") } ?? "-"
        let key = [place.timeZoneID, place.countryCode ?? "", days, "\(place.workStart ?? -1)", "\(place.workEnd ?? -1)",
                   "\(start)", "\(end)", "\(Holidays.counted)", "\(working)", "\(base.timeIntervalSinceReferenceDate)"]
            .joined(separator: "|")
        if let hit = cache[key] { return hit }
        if cache.count > 400 { cache.removeAll() }

        func flips(_ t: Date) -> Bool { WorkWeek.isWorking(place, at: t, start: start, end: end) != working }
        var result: Date?
        var previous = base
        for h in 1...(8 * 24) {
            let t = base.addingTimeInterval(Double(h) * 3600)
            if flips(t) {
                result = t
                for q in 1...3 {
                    let u = previous.addingTimeInterval(Double(q) * 900)
                    if flips(u) { result = u; break }
                }
                break
            }
            previous = t
        }
        cache[key] = result
        return result
    }
}

/// A city's working status as a small outlined capsule: an icon and the status in its colour, with
/// the detail after a dot in tall cards. On a photo it sits on a translucent dark backing.
struct StatusPill: View {
    let status: WorkStatus
    var showDetail = false
    var scale: CGFloat = 1
    var backed = false

    var body: some View {
        // The detail ("until 5 PM") goes before anything would be cut: the pill never ends in an
        // ellipsis (VoiceOver still hears the detail through `status.spoken`).
        ViewThatFits(in: .horizontal) {
            pill(label(detail: true))
            pill(label(detail: false))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spoken)
    }

    private func pill(_ text: Text) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
                .font(.system(size: 11 * scale, weight: .semibold))
            text
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background {
            // Dark enough that the status reads over a bright day photo too.
            if backed { Capsule().fill(Color.black.opacity(0.68)) }
        }
        .overlay(Capsule().strokeBorder(status.color.opacity(0.5), lineWidth: 1))
    }

    private func label(detail showsDetail: Bool) -> Text {
        let title = Text(status.title).font(.system(size: 12 * scale, weight: .semibold))
        guard showsDetail, showDetail, let detail = status.detail else { return title }
        return title + Text(" \u{00B7} " + detail).font(.system(size: 12 * scale, weight: .medium)).foregroundStyle(status.color.opacity(0.9))
    }
}

/// Settings → About → Photo Credits: where the city photos come from, built in and downloaded,
/// with each one's author and licence, and a link where it has one (only photos from before the
/// manifest). The AI-generated city plates ("Generated with AI for Meridian", no source) show
/// without a link; default scenes aren't listed.
struct PhotoCreditsView: View {
    @ObservedObject private var photos = CityPhotos.shared

    var body: some View {
        let downloaded = photos.credits
        let bundled = SkylineArt.bundledCredits
        Form {
            Section {
                ForEach(bundled) { credit in creditRow(credit) }
            } header: {
                caption("Built In")
            } footer: {
                caption(Self.builtInFooter(bundled))
            }
            .meridianSection()
            if !downloaded.isEmpty {
                Section {
                    ForEach(downloaded) { credit in creditRow(credit) }
                } header: {
                    caption("Downloaded")
                } footer: {
                    caption(Self.downloadedFooter)
                }
                .meridianSection()
            }
        }
        .meridianForm()
        .navigationTitle("Photo Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func creditRow(_ credit: PhotoCreditItem) -> some View {
        if let url = credit.source {
            Link(destination: url) { creditText(credit) }
        } else {
            creditText(credit)
        }
    }

    private func creditText(_ credit: PhotoCreditItem) -> some View {
        // An AI plate reads "Generated with AI for Meridian" alone (its licence says the same).
        let author = credit.author.flatMap { $0.isEmpty ? nil : $0 }
        let parts = SkylineArt.isGenerated(credit) ? [author ?? "Generated with AI for Meridian"]
            : [credit.author, credit.license].compactMap { $0 }
        let line = parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(credit.city).foregroundStyle(.white)
            Text(line.isEmpty ? (credit.fallback ?? "Generated with AI for Meridian") : line)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .lineLimit(2)
        }
    }

    /// The downloaded section's note: the hosted plates are AI-generated for Meridian.
    private static let downloadedFooter = "City photos generated with AI for Meridian. Downloaded once and kept on your iPhone."

    /// The built-in section's note: the photos were made with AI for Meridian.
    private static func builtInFooter(_ credits: [PhotoCreditItem]) -> String {
        "City photos generated with AI for Meridian. Other cities show a scene that suits where they are."
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            .textCase(nil)
    }
}
