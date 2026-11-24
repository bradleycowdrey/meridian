#if os(macOS)
import SwiftUI
import ImageIO
import Foundation

/// A photo's credit as Settings → About → Photo Credits lists it.
struct MacPhotoCredit: Identifiable, Hashable {
    let id: String
    let city: String
    let author: String?
    let license: String?
    let source: URL?
}

/// What matching a city against plates-remote.json needs from an index entry or an alias: its
/// zone and country.
fileprivate protocol MacRemoteMatchable {
    var zone: String? { get }
    var cc: String? { get }
}

/// The city photos bundled with the Mac app and its widget: Resources/Skylines/skyline_<key>.jpg
/// (day) and skyline_<key>_night.jpg, named by Resources/skylines.json. scripts/build-app.sh
/// copies them in; the app holds the full-size photos (the 1536 x 512 city plates) and the widget,
/// which is sandboxed, its own 600 px copies. Without them (a bare `swift run`) every city shows
/// the sky gradient.
///
/// Cities without a built-in photo: an alias in Resources/plates-remote.json can point one at a
/// built-in photo ("Brooklyn": New York's); otherwise, when the index has a hosted AI plate for it,
/// the app (PlateDownloads) downloads its day and night photos once into `platesDirectory`, where
/// the Mac App Store build's widget reads them too (the DMG widget keeps to built-in photos).
/// Precedence: built-in photo, alias, hosted plate, the sky.
enum MacSkylines {
    // MARK: The manifest

    private struct Credit: Decodable {
        var author: String?
        var license: String?
        var licenseUrl: String?
        var source: String?
    }

    private struct Night: Decodable {
        var file: String?
        var credit: Credit?
        /// The night photo's skyline band: its vertical centre, 0 (top) to 1 (bottom).
        var focus: Double?
        /// The night photo's landmark: its horizontal position, 0 (left) to 1 (right). Manifest v3;
        /// nil in v2 files (then 0.5, the photo's middle).
        var focusX: Double?
        /// The night photo's landmark tip: its height, 0 (top) to 1 (bottom). Optional; nil: no
        /// tip rule.
        var top: Double?

        private enum CodingKeys: String, CodingKey { case file, credit, focus, focusX, top }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            file = try? c.decodeIfPresent(String.self, forKey: .file)
            credit = try? c.decodeIfPresent(Credit.self, forKey: .credit)
            focus = try? c.decodeIfPresent(Double.self, forKey: .focus)
            focusX = try? c.decodeIfPresent(Double.self, forKey: .focusX)
            top = try? c.decodeIfPresent(Double.self, forKey: .top)
        }
    }

    private struct Entry: Decodable {
        let key: String
        var names: [String] = []
        var zone: String?
        var file: String?
        var credit: Credit?
        /// nil when the photo pipeline found no night photo for the city.
        var night: Night?
        /// The day photo's skyline band: its vertical centre, 0 (top) to 1 (bottom).
        var focus: Double?
        /// The day photo's landmark: its horizontal position, 0 (left) to 1 (right). Manifest v3;
        /// nil in v2 files (then 0.5, the photo's middle).
        var focusX: Double?
        /// The day photo's landmark tip: its height, 0 (top) to 1 (bottom). Optional; nil: no tip rule.
        var top: Double?

        private enum CodingKeys: String, CodingKey { case key, names, zone, file, credit, night, focus, focusX, top }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
            zone = try? c.decodeIfPresent(String.self, forKey: .zone)
            file = try? c.decodeIfPresent(String.self, forKey: .file)
            credit = try? c.decodeIfPresent(Credit.self, forKey: .credit)
            night = try? c.decodeIfPresent(Night.self, forKey: .night)
            focus = try? c.decodeIfPresent(Double.self, forKey: .focus)
            focusX = try? c.decodeIfPresent(Double.self, forKey: .focusX)
            top = try? c.decodeIfPresent(Double.self, forKey: .top)
        }
    }

    /// An entry that fails to decode is skipped rather than losing the whole manifest.
    private struct LenientEntry: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }

    /// Any JSON object key, for reading the v3 file's top level.
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// The whole file. v2 is a bare array of entries; v3 is an object with "version": 3 and the
    /// entries under one array-valued key ("entries", "cities", "skylines" or "photos" preferred,
    /// else the first other key holding an array of entries).
    private struct ManifestFile: Decodable {
        var entries: [Entry] = []

        init(from decoder: Decoder) throws {
            if let list = try? decoder.singleValueContainer().decode([LenientEntry].self) {
                entries = list.compactMap { $0.entry }
                return
            }
            let c = try decoder.container(keyedBy: AnyKey.self)
            let preferred = ["entries", "cities", "skylines", "photos"]
            let first: [AnyKey] = preferred.compactMap { AnyKey(stringValue: $0) }.filter { c.contains($0) }
            let others: [AnyKey] = c.allKeys
                .filter { !preferred.contains($0.stringValue) && $0.stringValue != "version" }
                .sorted { $0.stringValue < $1.stringValue }
            let keys = first + others
            for key in keys {
                if let list = try? c.decode([LenientEntry].self, forKey: key) {
                    let found = list.compactMap { $0.entry }
                    if !found.isEmpty {
                        entries = found
                        return
                    }
                }
            }
        }
    }

    /// skylines.json (v2 or v3) from the bundle; empty when it isn't there.
    private static let manifest: [Entry] = {
        guard let url = Bundle.main.url(forResource: "skylines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ManifestFile.self, from: data)
        else { return [] }
        return file.entries
    }()

    /// The manifest's entries by every name they go by (normalised).
    private static let index: [String: [Entry]] = {
        var out: [String: [Entry]] = [:]
        for entry in manifest {
            let names = entry.names.isEmpty ? [entry.key] : entry.names
            for name in names {
                let n = normalize(name)
                guard !n.isEmpty else { continue }
                out[n, default: []].append(entry)
            }
        }
        return out
    }()

    /// The manifest's entries by key (the first one with each key).
    private static let byKey: [String: Entry] = {
        var out: [String: Entry] = [:]
        for entry in manifest where out[entry.key] == nil { out[entry.key] = entry }
        return out
    }()

    // MARK: The hosted plates' index (plates-remote.json)

    private struct RemoteNight: Decodable {
        var focus: Double?
        var focusX: Double?
        var top: Double?

        private enum CodingKeys: String, CodingKey { case focus, focusX, top }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            focus = try? c.decodeIfPresent(Double.self, forKey: .focus)
            focusX = try? c.decodeIfPresent(Double.self, forKey: .focusX)
            top = try? c.decodeIfPresent(Double.self, forKey: .top)
        }
    }

    /// A city with a hosted AI plate (day and night), downloaded once: base + key + "-day.jpg"
    /// and base + key + "-night.jpg". Placed by its own focus, focusX and top, like a built-in plate.
    private struct RemoteEntry: Decodable, MacRemoteMatchable {
        let key: String
        var names: [String] = []
        var zone: String?
        var cc: String?
        var focus: Double?
        var focusX: Double?
        var top: Double?
        var night: RemoteNight?

        private enum CodingKeys: String, CodingKey { case key, names, zone, cc, focus, focusX, top, night }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
            zone = try? c.decodeIfPresent(String.self, forKey: .zone)
            cc = try? c.decodeIfPresent(String.self, forKey: .cc)
            focus = try? c.decodeIfPresent(Double.self, forKey: .focus)
            focusX = try? c.decodeIfPresent(Double.self, forKey: .focusX)
            top = try? c.decodeIfPresent(Double.self, forKey: .top)
            night = try? c.decodeIfPresent(RemoteNight.self, forKey: .night)
        }
    }

    /// Another name for a city with a built-in photo ("Brooklyn" -> newyork): that photo, no download.
    private struct RemoteAlias: Decodable, MacRemoteMatchable {
        var names: [String] = []
        var zone: String?
        var cc: String?
        let key: String

        private enum CodingKeys: String, CodingKey { case names, zone, cc, key }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
            zone = try? c.decodeIfPresent(String.self, forKey: .zone)
            cc = try? c.decodeIfPresent(String.self, forKey: .cc)
            key = try c.decode(String.self, forKey: .key)
        }
    }

    /// An entry or alias that fails to decode is skipped rather than losing the whole index.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// The whole file: {"version": 1, "base": "https://…/", "cities": [...], "aliases": [...]}.
    private struct RemoteFile: Decodable {
        var base: URL?
        var cities: [RemoteEntry] = []
        var aliases: [RemoteAlias] = []

        private enum CodingKeys: String, CodingKey { case base, cities, aliases }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Only an https base is used; it must end in "/" so the key is a file in it.
            if let text = try? c.decodeIfPresent(String.self, forKey: .base), text.hasSuffix("/"),
               let url = URL(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false {
                base = url
            }
            cities = ((try? c.decodeIfPresent([Lenient<RemoteEntry>].self, forKey: .cities)) ?? [])
                .compactMap { $0.value }
                .filter { MacSkylines.validPlateKey($0.key) }
            aliases = ((try? c.decodeIfPresent([Lenient<RemoteAlias>].self, forKey: .aliases)) ?? [])
                .compactMap { $0.value }
        }
    }

    /// plates-remote.json from the bundle; nil when it isn't there (then no city gets a hosted plate).
    private static let remote: RemoteFile? = {
        guard let url = Bundle.main.url(forResource: "plates-remote", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RemoteFile.self, from: data)
    }()

    /// The hosted plates by every name they go by (normalised).
    private static let remoteIndex: [String: [RemoteEntry]] = {
        var out: [String: [RemoteEntry]] = [:]
        for entry in remote?.cities ?? [] {
            for name in entry.names.isEmpty ? [entry.key] : entry.names {
                let n = normalize(name)
                guard !n.isEmpty else { continue }
                out[n, default: []].append(entry)
            }
        }
        return out
    }()

    /// The hosted plates by key (the first one with each key).
    private static let remoteByKey: [String: RemoteEntry] = {
        var out: [String: RemoteEntry] = [:]
        for entry in remote?.cities ?? [] where out[entry.key] == nil { out[entry.key] = entry }
        return out
    }()

    /// The aliases by every name they go by (normalised).
    private static let aliasIndex: [String: [RemoteAlias]] = {
        var out: [String: [RemoteAlias]] = [:]
        for alias in remote?.aliases ?? [] {
            for name in alias.names {
                let n = normalize(name)
                guard !n.isEmpty else { continue }
                out[n, default: []].append(alias)
            }
        }
        return out
    }()

    /// A hosted plate's key is used in its URL and its file names: lowercase letters, digits and
    /// hyphens only ("chengdu-cn"), so it can never reach outside either.
    fileprivate static func validPlateKey(_ key: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return !key.isEmpty && key.count <= 80 && key.allSatisfy { allowed.contains($0) }
    }

    /// The best index entry or alias for a city with this name: the same zone, else one on the same
    /// clock all year (as for skylines.json), else one in the same country as the city's zone (the
    /// city list can use another zone of that country: Asia/Chongqing for Asia/Shanghai).
    private static func bestRemote<T: MacRemoteMatchable>(_ list: [T], timeZoneID: String) -> T? {
        if let exact = list.first(where: { $0.zone == timeZoneID }) { return exact }
        if let fits = list.first(where: { zoneFits($0.zone, timeZoneID) }) { return fits }
        guard let country = WorkWeek.countryByZone[timeZoneID]?.uppercased(), !country.isEmpty else { return nil }
        return list.first(where: { $0.cc?.uppercased() == country })
    }

    /// Lowercased, without accents or spaces at the ends ("São Paulo" -> "sao paulo").
    private static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a manifest entry's time zone fits the city: the same zone, or one on the same clock
    /// all year (Asia/Calcutta and Asia/Kolkata); never Portland, Maine for Portland, Oregon.
    private static func zoneFits(_ zone: String?, _ timeZoneID: String) -> Bool {
        guard let zone, !zone.isEmpty, zone != timeZoneID else { return true }
        guard let entryZone = TimeZone(identifier: zone) else { return true }
        guard let cityZone = TimeZone(identifier: timeZoneID) else { return false }
        // Compared on two fixed dates (mid-January and mid-July 2026), so only zones that keep the
        // same time all year match, not ones that agree just today.
        let dates = [Date(timeIntervalSince1970: 1768478400), Date(timeIntervalSince1970: 1784116800)]
        return dates.allSatisfy { entryZone.secondsFromGMT(for: $0) == cityZone.secondsFromGMT(for: $0) }
    }

    // MARK: Files

    /// Resources/Skylines in this bundle (the app's, or the widget's own).
    private static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Skylines", isDirectory: true)

    /// The JPEGs found there, by file name.
    private static let files: Set<String> = {
        guard let folder = directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return Set(names.filter { $0.hasSuffix(".jpg") })
    }()

    private static func fileName(key: String, night: Bool) -> String {
        night ? "skyline_\(key)_night.jpg" : "skyline_\(key).jpg"
    }

    /// The JPEGs found in this bundle's Resources/Skylines.
    static var photoCount: Int { files.count }

    // MARK: Downloaded plates

    /// A hosted plate's key as the rest of this file sees it ("plate:chengdu-cn"), so it never
    /// collides with a built-in one ("newyork").
    private static let hostedPrefix = "plate:"

    /// The hosted plate's own key ("chengdu-cn") for a key from `key(name:timeZoneID:)`, or nil
    /// when that is a built-in photo.
    private static func hostedKey(_ key: String) -> String? {
        key.hasPrefix(hostedPrefix) ? String(key.dropFirst(hostedPrefix.count)) : nil
    }

    /// Where the app keeps the hosted plates it downloaded: Plates/<key>-day.jpg and
    /// Plates/<key>-night.jpg. The Mac App Store build: the App Group container the app and its
    /// widget share, so the widget shows them too. The DMG build: ~/Library/Application Support/
    /// Meridian/Plates, for the app only: the DMG widget has never shown downloaded photos, and
    /// keeps to its built-in ones (nil there, so its downloaded cities keep their sky).
    static var platesDirectory: URL? {
        #if APPSTORE
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "2XV97FZ86G.com.bradcowdrey.meridian")?
            .appendingPathComponent("Plates", isDirectory: true)
        #else
        if isWidget { return nil }
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Meridian/Plates", isDirectory: true)
        #endif
    }

    private static func plateFileName(_ hosted: String, night: Bool) -> String {
        hosted + (night ? "-night.jpg" : "-day.jpg")
    }

    /// A downloaded plate's file, nil when it isn't on this Mac.
    private static func plateFile(_ hosted: String, night: Bool) -> URL? {
        guard let url = platesDirectory?.appendingPathComponent(plateFileName(hosted, night: night)),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The Settings → Cities → Download City Photos switch (UserDefaults, as on iPhone; on unless
    /// turned off). Off: no hosted plate is downloaded or shown.
    static let downloadsDefaultsKey = "downloadCityPhotos"
    /// Written into Plates while the switch is off, so the widget (which can't read the app's
    /// settings) shows no downloaded plate either.
    private static let downloadsOffMarker = "downloads-off"
    private static let isWidget = Bundle.main.bundleURL.pathExtension == "appex"

    static var downloadsEnabled: Bool {
        if isWidget {
            guard let folder = platesDirectory else { return false }
            return !FileManager.default.fileExists(atPath: folder.appendingPathComponent(downloadsOffMarker).path)
        }
        return UserDefaults.standard.object(forKey: downloadsDefaultsKey) as? Bool ?? true
    }

    /// The app sets the switch here: saved, and mirrored for the widget.
    static func setDownloadsEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: downloadsDefaultsKey)
        syncDownloadsMarker()
    }

    /// Puts the widget's copy of the switch in step with the app's (the app calls it at launch).
    static func syncDownloadsMarker() {
        guard !isWidget, let folder = platesDirectory else { return }
        let marker = folder.appendingPathComponent(downloadsOffMarker)
        let fm = FileManager.default
        if downloadsEnabled {
            if fm.fileExists(atPath: marker.path) { try? fm.removeItem(at: marker) }
        } else if !fm.fileExists(atPath: marker.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data().write(to: marker, options: .atomic)
        }
    }

    /// A hosted plate a city wants and this Mac doesn't have yet: its key and the day and night
    /// URLs (base + key + "-day.jpg" / "-night.jpg").
    struct HostedPlate: Hashable, Sendable {
        let key: String
        let day: URL
        let night: URL
    }

    /// The hosted plate to download for a city: nil when it has a built-in photo (its own or an
    /// alias's), has no hosted plate, or its plate is already downloaded (never asked for again).
    /// Doesn't look at the switch.
    static func plateToDownload(name: String, timeZoneID: String) -> HostedPlate? {
        let found = match(name: name, timeZoneID: timeZoneID)
        guard found.hasPrefix("h:"), let base = remote?.base else { return nil }
        let hosted = String(found.dropFirst(2))
        if plateFile(hosted, night: false) != nil && plateFile(hosted, night: true) != nil { return nil }
        guard let day = URL(string: base.absoluteString + hosted + "-day.jpg"),
              let night = URL(string: base.absoluteString + hosted + "-night.jpg") else { return nil }
        return HostedPlate(key: hosted, day: day, night: night)
    }

    /// Keeps a downloaded plate (both photos): the night photo first, then the day one, so a day
    /// photo on disk always has its night photo beside it. False when either couldn't be written.
    static func storePlate(key: String, day: Data, night: Data) -> Bool {
        guard validPlateKey(key), let folder = platesDirectory else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try night.write(to: folder.appendingPathComponent(plateFileName(key, night: true)), options: .atomic)
            try day.write(to: folder.appendingPathComponent(plateFileName(key, night: false)), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: Lookup

    private static let lock = NSLock()
    /// What each city matched, by name and zone (see `match`).
    private static var keyCache: [String: String] = [:]
    /// Decoded photos, by "<key>|<night>|<maxPixel>".
    private static var imageCache: [String: CGImage] = [:]
    private static let imageCacheLimit = 40

    /// What a city matches, worked out once: "b:<key>" a built-in photo (its own in skylines.json,
    /// else an alias's in plates-remote.json), "h:<key>" a hosted plate (shown once downloaded),
    /// "" nothing. In that order: a built-in photo always wins, and a city with neither keeps its sky.
    private static func match(name: String, timeZoneID: String) -> String {
        let cacheKey = name + "|" + timeZoneID
        lock.lock()
        let hit = keyCache[cacheKey]
        lock.unlock()
        if let hit { return hit }

        let n = normalize(name)
        var result = ""
        // 1. Its own built-in photo, by name and time zone.
        let candidates = index[n] ?? []
        let exact = candidates.first(where: { $0.zone == timeZoneID })
        if let found = (exact ?? candidates.first(where: { zoneFits($0.zone, timeZoneID) }))?.key,
           files.contains(fileName(key: found, night: false)) {
            result = "b:" + found
        }
        // 2. Another name for a city with a built-in photo ("Brooklyn": New York's).
        if result.isEmpty, let alias = bestRemote(aliasIndex[n] ?? [], timeZoneID: timeZoneID),
           byKey[alias.key] != nil, files.contains(fileName(key: alias.key, night: false)) {
            result = "b:" + alias.key
        }
        // 3. A hosted AI plate, downloaded once.
        if result.isEmpty, remote?.base != nil,
           let plate = bestRemote(remoteIndex[n] ?? [], timeZoneID: timeZoneID) {
            result = "h:" + plate.key
        }

        lock.lock()
        if keyCache.count > 400 { keyCache.removeAll() }
        keyCache[cacheKey] = result
        lock.unlock()
        return result
    }

    /// The photo's key for a city (matched by name and time zone), or nil when it has no photo: no
    /// built-in one in the bundle, and no hosted plate downloaded (or Download City Photos is off).
    /// A hosted plate's key starts "plate:".
    static func key(name: String, timeZoneID: String) -> String? {
        let found = match(name: name, timeZoneID: timeZoneID)
        if found.hasPrefix("b:") { return String(found.dropFirst(2)) }
        if found.hasPrefix("h:") {
            let hosted = String(found.dropFirst(2))
            // Checked each time (not cached): the app downloads it later, and the widget's process
            // outlives that.
            guard downloadsEnabled, plateFile(hosted, night: false) != nil else { return nil }
            return hostedPrefix + hosted
        }
        return nil
    }

    /// Whether the city wants its night photo at `date`: from sunset until an hour before sunrise.
    /// A zone with no known place (UTC, an offset) goes by the clock: night outside 7:00–19:00.
    static func wantsNight(timeZoneID: String, latitude: Double?, longitude: Double?, at date: Date) -> Bool {
        let zone = TimeZone(identifier: timeZoneID)
        let phase: Sun.Phase?
        if let latitude, let longitude, let zone {
            phase = Sun.phase(lat: latitude, lon: longitude, zone: zone, at: date)
        } else {
            phase = Sun.phase(zoneID: timeZoneID, at: date)
        }
        switch phase {
        case .night(let rises)?:
            return rises.timeIntervalSince(date) >= 3600
        case .allNight?:
            return true
        case .day?, .allDay?:
            return false
        case nil:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone ?? .current
            let hour = calendar.component(.hour, from: date)
            return !(7..<19).contains(hour)
        }
    }

    // MARK: Decoding

    /// The city's day or night photo, at most `maxPixel` on its longer side. Decoded once and kept;
    /// safe to call from any thread. nil when the city has no such photo.
    static func image(name: String, timeZoneID: String, night: Bool, maxPixel: Int) -> CGImage? {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return nil }
        return image(key: key, night: night, maxPixel: maxPixel)
    }

    /// The same, decoded off the main thread.
    static func load(name: String, timeZoneID: String, night: Bool, maxPixel: Int) async -> CGImage? {
        await Task.detached(priority: .utility) {
            MacSkylines.image(name: name, timeZoneID: timeZoneID, night: night, maxPixel: maxPixel)
        }.value
    }

    private static func cacheKey(key: String, night: Bool, maxPixel: Int) -> String {
        "\(key)|\(night)|\(maxPixel)"
    }

    /// A photo already decoded, without decoding one.
    fileprivate static func cached(key: String, night: Bool, maxPixel: Int) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return imageCache[cacheKey(key: key, night: night, maxPixel: maxPixel)]
    }

    fileprivate static func image(key: String, night: Bool, maxPixel: Int) -> CGImage? {
        if let hit = cached(key: key, night: night, maxPixel: maxPixel) { return hit }
        guard let url = photoFile(key: key, night: night),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        lock.lock()
        if imageCache.count >= imageCacheLimit { imageCache.removeAll() }
        imageCache[cacheKey(key: key, night: night, maxPixel: maxPixel)] = decoded
        lock.unlock()
        return decoded
    }

    /// The file of a key's day or night photo: built in (this bundle's Resources/Skylines), or a
    /// downloaded plate (Plates, while Download City Photos is on). nil when there is none.
    private static func photoFile(key: String, night: Bool) -> URL? {
        if let hosted = hostedKey(key) {
            guard downloadsEnabled else { return nil }
            return plateFile(hosted, night: night)
        }
        let file = fileName(key: key, night: night)
        guard files.contains(file) else { return nil }
        return directory?.appendingPathComponent(file)
    }

    /// Which photo a city shows: its night photo after dark when it has one, else its day photo
    /// (darkened after dark). nil when the city has no photo.
    fileprivate static func pick(name: String, timeZoneID: String, night: Bool) -> MacSkylinePick? {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return nil }
        guard night else {
            return MacSkylinePick(key: key, night: false, dimmed: false,
                                  focus: focus(key: key, night: false), focusX: focusX(key: key, night: false))
        }
        if photoFile(key: key, night: true) != nil {
            return MacSkylinePick(key: key, night: true, dimmed: false,
                                  focus: focus(key: key, night: true), focusX: focusX(key: key, night: true))
        }
        return MacSkylinePick(key: key, night: false, dimmed: true,
                              focus: focus(key: key, night: false), focusX: focusX(key: key, night: false))
    }

    // MARK: Framing

    /// Where a photo's skyline sits when the manifest doesn't say: 62 % of the way down.
    static let defaultFocus: CGFloat = 0.62

    /// The vertical centre of the skyline band in the city's day (`night` false) or night photo,
    /// 0 (top) to 1 (bottom), from skylines.json; `defaultFocus` when it has none. Pass the photo
    /// actually shown: after dark with no night photo that is the day photo, so `night: false`.
    static func focus(name: String, timeZoneID: String, night: Bool) -> CGFloat {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return defaultFocus }
        return focus(key: key, night: night)
    }

    /// A photo's measured numbers (skyline band, landmark, landmark tip), from skylines.json for
    /// a built-in photo or plates-remote.json for a hosted plate (its night entry for the night
    /// photo; the day numbers if it has none).
    private struct Numbers {
        var focus: Double?
        var focusX: Double?
        var top: Double?
    }

    private static func numbers(key: String, night: Bool) -> Numbers {
        if let hosted = hostedKey(key) {
            let entry = remoteByKey[hosted]
            if night, let n = entry?.night { return Numbers(focus: n.focus, focusX: n.focusX, top: n.top) }
            return Numbers(focus: entry?.focus, focusX: entry?.focusX, top: entry?.top)
        }
        let entry = byKey[key]
        return night
            ? Numbers(focus: entry?.night?.focus, focusX: entry?.night?.focusX, top: entry?.night?.top)
            : Numbers(focus: entry?.focus, focusX: entry?.focusX, top: entry?.top)
    }

    private static func focus(key: String, night: Bool) -> CGFloat {
        let value = numbers(key: key, night: night).focus
        guard let value, value.isFinite else { return defaultFocus }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Where a photo's landmark sits when the manifest doesn't say (v2 files): its middle.
    static let defaultFocusX: CGFloat = 0.5

    /// The horizontal position of the landmark in the city's day (`night` false) or night photo,
    /// 0 (left) to 1 (right), from skylines.json (v3 "focusX"); `defaultFocusX` when it has none.
    /// Pass the photo actually shown: after dark with no night photo that is the day photo, so
    /// `night: false`.
    static func focusX(name: String, timeZoneID: String, night: Bool) -> CGFloat {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return defaultFocusX }
        return focusX(key: key, night: night)
    }

    private static func focusX(key: String, night: Bool) -> CGFloat {
        let value = numbers(key: key, night: night).focusX
        guard let value, value.isFinite else { return defaultFocusX }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Whether the city's day (`night` false) or night photo has a measured landmark (skylines.json
    /// v3 "focusX": an AI plate). The small widget then puts the landmark in its clear right-hand
    /// column; otherwise the photo stays centred. Pass the photo actually shown, as for `focusX`.
    static func landmarkKnown(name: String, timeZoneID: String, night: Bool) -> Bool {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return false }
        let value = numbers(key: key, night: night).focusX
        guard let value else { return false }
        return value.isFinite
    }

    /// The height of the landmark's tip in the city's day (`night` false) or night photo, 0 (top)
    /// to 1 (bottom), from skylines.json ("top"); nil when it has none (no tip rule: the photo is
    /// placed as before). Pass the photo actually shown: after dark with no night photo that is the
    /// day photo, so `night: false`.
    static func top(name: String, timeZoneID: String, night: Bool) -> CGFloat? {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return nil }
        let value = numbers(key: key, night: night).top
        guard let value, value.isFinite else { return nil }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Where to draw a `imageSize` photo so it fills a `frame`-sized box: the rect (in the box's
    /// coordinates) for the scaled photo. Scaled just enough to cover the box, then slid so the
    /// photo's landmark (`landmark`, 0-1 of its width) lands at `targetX` (points from the box's
    /// leading edge; nil = the box's middle). When covering the box keeps it from getting there,
    /// it is scaled up to 15 % more, only as much as reaching the target takes, never more.
    /// Vertically the point `focusY` of the way down the photo sits at the box's middle. Always
    /// clamped so the photo covers the box, with no empty edge.
    static func photoRect(imageSize: CGSize, in frame: CGSize, targetX: CGFloat?, landmark: CGFloat,
                          focusY: CGFloat) -> CGRect {
        let iw = max(imageSize.width, 1), ih = max(imageSize.height, 1)
        let fw = max(frame.width, 0), fh = max(frame.height, 0)
        let cover = max(fw / iw, fh / ih)
        let target = min(max(targetX ?? fw / 2, 0), fw)
        let l = landmark.isFinite ? min(max(landmark, 0), 1) : defaultFocusX
        // The least scale at which target - l * w lies within [fw - w, 0]: the landmark's left
        // side must reach the target (l * w >= target) and so must its right side
        // ((1 - l) * w >= fw - target). A landmark at an edge can't get there at any scale, so
        // that takes the full 15 %, as close as it may come.
        var wanted: CGFloat = 0
        if target > 0 { wanted = max(wanted, l > 0 ? target / (l * iw) : .infinity) }
        if target < fw { wanted = max(wanted, l < 1 ? (fw - target) / ((1 - l) * iw) : .infinity) }
        let scale = max(cover, min(cover * 1.15, wanted))
        let w = iw * scale, h = ih * scale
        let x = min(max(target - l * w, fw - w), 0)
        let y = min(max(fh / 2 - focusY * h, fh - h), 0)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Credits

    private static let creditList: [MacPhotoCredit] = {
        var seen = Set<String>()
        var out: [MacPhotoCredit] = []
        for entry in manifest {
            guard seen.insert(entry.key).inserted else { continue }
            let city = entry.names.first ?? entry.key
            out.append(MacPhotoCredit(id: entry.key, city: city, author: text(entry.credit?.author),
                                      license: text(entry.credit?.license), source: link(entry.credit?.source)))
            if let night = entry.night, night.file != nil || night.credit != nil {
                out.append(MacPhotoCredit(id: entry.key + "-night", city: city + ", night",
                                          author: text(night.credit?.author), license: text(night.credit?.license),
                                          source: link(night.credit?.source)))
            }
        }
        return out.sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }()

    /// A credit's text, nil when missing or blank.
    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A credit's source as a link, nil when missing, blank or not a web address (an AI plate has
    /// "source": ""), so the list never shows a link that goes nowhere.
    private static func link(_ value: String?) -> URL? {
        guard let string = text(value), let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// The bundled photos' credits (day, and night where there is one), A to Z by city.
    static var credits: [MacPhotoCredit] { creditList }

    /// The hosted plates downloaded to this Mac (day, and night where it is on disk), with the AI
    /// credit and no link, A to Z by city. Read from disk each time (the Photo Credits sheet).
    static var downloadedCredits: [MacPhotoCredit] {
        guard let folder = platesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let onDisk = Set(names)
        let author = "Generated with AI for Meridian", license = "AI-generated image"
        var seen = Set<String>()
        var out: [MacPhotoCredit] = []
        for entry in remote?.cities ?? [] {
            guard seen.insert(entry.key).inserted,
                  onDisk.contains(plateFileName(entry.key, night: false)) else { continue }
            let city = entry.names.first ?? entry.key
            out.append(MacPhotoCredit(id: hostedPrefix + entry.key, city: city, author: author,
                                      license: license, source: nil))
            if onDisk.contains(plateFileName(entry.key, night: true)) {
                out.append(MacPhotoCredit(id: hostedPrefix + entry.key + "-night", city: city + ", night",
                                          author: author, license: license, source: nil))
            }
        }
        return out.sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }
}

/// The photo a backdrop shows: the city's key, whether it is the night photo, and whether a day
/// photo stands in after dark (then darkened).
fileprivate struct MacSkylinePick {
    let key: String
    let night: Bool
    let dimmed: Bool
    /// The shown photo's skyline band, 0 (top) to 1 (bottom).
    let focus: CGFloat
    /// The shown photo's landmark, 0 (left) to 1 (right).
    let focusX: CGFloat

    func id(maxPixel: Int) -> String { "\(key)|\(night)|\(maxPixel)|\(dimmed)" }
}

fileprivate func macSkylineTone(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// A photo filling its frame, laid out by `MacSkylines.photoRect`: scaled just enough to cover it,
/// its landmark (`focusX`, 0-1 of the photo's width) slid to `targetX` (points from the frame's
/// leading edge; nil = the middle) with up to 15 % more zoom when needed, and the skyline band
/// (`focusY` of the way down the photo) at the frame's vertical middle.
fileprivate struct MacSkylinePhoto: View {
    let image: CGImage
    let dimmed: Bool
    var targetX: CGFloat? = nil
    var focusX: CGFloat = MacSkylines.defaultFocusX
    var focusY: CGFloat = MacSkylines.defaultFocus

    var body: some View {
        GeometryReader { geo in
            let rect = MacSkylines.photoRect(imageSize: CGSize(width: image.width, height: image.height),
                                             in: geo.size, targetX: targetX, landmark: focusX, focusY: focusY)
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .overlay { if dimmed { Color.black.opacity(0.45) } }
        .clipped()
    }
}

/// The city's photo for the sun there at `date` (night photo after dark), else the sky gradient.
/// Fills its frame; no scrim, no clip.
struct MacSkylineBackdrop: View {
    private let name: String
    private let timeZoneID: String
    private let latitude: Double?
    private let longitude: Double?
    private let date: Date
    private let maxPixel: Int
    private let synchronous: Bool
    private let targetX: CGFloat?

    private struct Shown {
        let id: String
        let image: CGImage
        let dimmed: Bool
        let focus: CGFloat
        let focusX: CGFloat
    }

    @State private var shown: Shown?

    /// `synchronous` decodes in `body` (widgets and ImageRenderer, which never run tasks);
    /// otherwise the photo is decoded off the main thread and fades in. `targetX` (points from the
    /// leading edge) is where the photo's landmark (skylines.json "focusX") goes: in a panel row
    /// the gap between the label and the hour tiles; nil puts it in the middle of the frame.
    init(name: String, timeZoneID: String, latitude: Double? = nil, longitude: Double? = nil,
         date: Date, maxPixel: Int = 1000, synchronous: Bool = false, targetX: CGFloat? = nil) {
        self.name = name
        self.timeZoneID = timeZoneID
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.maxPixel = maxPixel
        self.synchronous = synchronous
        self.targetX = targetX
    }

    private static let daySky = [macSkylineTone(0x3D74B0), macSkylineTone(0x1C3A5E)]
    private static let nightSky = [macSkylineTone(0x141E3C), macSkylineTone(0x0A0E1C)]

    var body: some View {
        let night = MacSkylines.wantsNight(timeZoneID: timeZoneID, latitude: latitude, longitude: longitude, at: date)
        let pick = MacSkylines.pick(name: name, timeZoneID: timeZoneID, night: night)
        let wanted = pick?.id(maxPixel: maxPixel) ?? ""
        ZStack {
            LinearGradient(colors: night ? Self.nightSky : Self.daySky, startPoint: .top, endPoint: .bottom)
            if synchronous {
                if let pick, let image = MacSkylines.image(key: pick.key, night: pick.night, maxPixel: maxPixel) {
                    MacSkylinePhoto(image: image, dimmed: pick.dimmed, targetX: targetX,
                                    focusX: pick.focusX, focusY: pick.focus)
                }
            } else if let shown {
                MacSkylinePhoto(image: shown.image, dimmed: shown.dimmed, targetX: targetX,
                                focusX: shown.focusX, focusY: shown.focus)
                    .id(shown.id)
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: shown?.id)
        .task(id: wanted) {
            guard !synchronous else { return }
            guard let pick else {
                shown = nil
                return
            }
            // Already decoded (the panel was open before): show it at once, no fade.
            if let ready = MacSkylines.cached(key: pick.key, night: pick.night, maxPixel: maxPixel) {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    shown = Shown(id: wanted, image: ready, dimmed: pick.dimmed, focus: pick.focus, focusX: pick.focusX)
                }
                return
            }
            let key = pick.key, isNight = pick.night, size = maxPixel
            let image = await Task.detached(priority: .utility) {
                MacSkylines.image(key: key, night: isNight, maxPixel: size)
            }.value
            guard !Task.isCancelled else { return }
            shown = image.map { Shown(id: wanted, image: $0, dimmed: pick.dimmed, focus: pick.focus, focusX: pick.focusX) }
        }
    }
}

/// Settings → About → Photo Credits: every bundled photo's author, licence and source.
struct MacPhotoCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    /// The hosted plates downloaded to this Mac, read when the sheet opens.
    @State private var downloaded: [MacPhotoCredit] = []

    init() {}

    var body: some View {
        let credits = MacSkylines.credits
        VStack(spacing: 0) {
            HStack {
                Text("Photo Credits")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            if credits.isEmpty && downloaded.isEmpty {
                Text("No city photos in this copy of Meridian.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if downloaded.isEmpty {
                List(credits) { credit in row(credit) }
            } else {
                List {
                    if !credits.isEmpty {
                        Section("Built in") {
                            ForEach(credits) { credit in row(credit) }
                        }
                    }
                    Section("Downloaded") {
                        ForEach(downloaded) { credit in row(credit) }
                    }
                }
            }
        }
        .onAppear { downloaded = MacSkylines.downloadedCredits }
        .frame(width: 420, height: 480)
        .preferredColorScheme(.dark)
    }

    private func row(_ credit: MacPhotoCredit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credit.city)
                    .font(.system(size: 13, weight: .medium))
                Text(Self.detail(credit))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let source = credit.source {
                Link("Source", destination: source)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 2)
    }

    /// "author · licence", or where the photo is from when neither is known.
    private static func detail(_ credit: MacPhotoCredit) -> String {
        let parts = [credit.author, credit.license].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Wikimedia Commons" : parts.joined(separator: " · ")
    }
}
#endif
