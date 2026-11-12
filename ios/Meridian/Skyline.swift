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

/// A photo credit: who took it, its licence, and where it lives on Wikimedia Commons.
struct SkylinePhotoCredit: Codable, Hashable {
    var author: String?
    var license: String?
    var licenseUrl: String?
    var source: String?
}

/// One city of Resources/Data/skylines.json (written by the photo pipeline): its photo's key
/// (asset "Skyline-<key>", the day photo), the names it goes by, its time zone, the day photo's
/// credit, and (manifest v2) its night photo (asset "Skyline-<key>-night"), or none.
struct SkylineManifestEntry: Decodable {
    /// A city's night photo: its file, credit and skyline focus.
    struct Night: Decodable {
        var file: String?
        var credit: SkylinePhotoCredit?
        /// How far down the night photo its skyline band's centre sits (0…1), or nil.
        var focus: Double?

        private enum CodingKeys: String, CodingKey { case file, credit, focus }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            file = try? c.decodeIfPresent(String.self, forKey: .file)
            credit = try? c.decodeIfPresent(SkylinePhotoCredit.self, forKey: .credit)
            focus = SkylineManifestEntry.unitFocus(try? c.decodeIfPresent(Double.self, forKey: .focus))
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

    private enum CodingKeys: String, CodingKey { case key, names, zone, file, credit, night, focus }

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
    }
}

/// A manifest entry that failed to decode is skipped rather than losing the whole manifest.
private struct LenientManifestEntry: Decodable {
    let entry: SkylineManifestEntry?
    init(from decoder: Decoder) throws { entry = try? SkylineManifestEntry(from: decoder) }
}

/// A photo for a card, and a name for it that stays the same (for the ink cache). `night` is a
/// real night photo, shown as taken (never tinted).
struct SkylinePhoto {
    let id: String
    let image: UIImage
    var night = false
    /// How far down the photo its skyline band's centre sits (0…1), from the manifest; nil for a
    /// downloaded photo (laid out at SkylineArt.defaultFocus).
    var focus: Double? = nil
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
        guard let url = Bundle.main.url(forResource: "skylines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([LenientManifestEntry].self, from: data)
        else { return nil }
        let entries = list.compactMap(\.entry)
        return entries.isEmpty ? nil : entries
    }()

    /// The manifest's entries by every name they go by (normalised).
    private static let index: [String: [SkylineManifestEntry]] = {
        var out: [String: [SkylineManifestEntry]] = [:]
        for entry in manifest ?? [] {
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
    private static func zoneFits(_ zone: String?, _ place: Place) -> Bool {
        guard let zone, !zone.isEmpty, zone != place.timeZoneID else { return true }
        guard let tz = TimeZone(identifier: zone) else { return true }
        // Compared on two fixed dates (mid-January and mid-July 2026), so only zones that keep the
        // same time all year (an old name for the same zone) match, not ones that agree just today.
        let dates = [Date(timeIntervalSince1970: 1768478400), Date(timeIntervalSince1970: 1784116800)]
        return dates.allSatisfy { tz.secondsFromGMT(for: $0) == place.timeZone.secondsFromGMT(for: $0) }
    }

    /// Answers so far, by name and zone ("" for none).
    private static var keyCache: [String: String] = [:]

    /// The bundled photo's key for a card (its city's name, for a person their city's), or nil.
    static func key(for place: Place) -> String? {
        let cacheKey = place.name + "|" + place.timeZoneID
        if let hit = keyCache[cacheKey] { return hit.isEmpty ? nil : hit }
        let result: String?
        if manifest == nil {
            result = legacyKey(for: place.name)
        } else {
            let candidates = index[normalize(place.name)] ?? []
            let exact = candidates.first(where: { $0.zone == place.timeZoneID })
            result = (exact ?? candidates.first(where: { zoneFits($0.zone, place) }))?.key
        }
        if keyCache.count > 400 { keyCache.removeAll() }
        keyCache[cacheKey] = result ?? ""
        return result
    }

    /// The bundled photo for a card (asset "Skyline-<key>"), or nil.
    static func bundledPhoto(for place: Place) -> UIImage? {
        key(for: place).flatMap { UIImage(named: "Skyline-\($0)") }
    }

    /// The card's day photo: bundled, else the one downloaded for it; nil to draw one.
    static func photo(for place: Place, downloaded: UIImage?) -> SkylinePhoto? {
        if let key = key(for: place), let image = UIImage(named: "Skyline-\(key)") {
            return SkylinePhoto(id: "b:" + key, image: image, focus: byKey[key]?.focus)
        }
        if let downloaded { return SkylinePhoto(id: "d:" + slug(for: place), image: downloaded) }
        return nil
    }

    /// The card's night photo, paired with its day photo: a bundled day photo takes only its own
    /// bundled night photo ("Skyline-<key>-night"), a downloaded one the night photo downloaded
    /// for it. nil when the city has none (the card then draws its skyline on the night sky).
    static func nightPhoto(for place: Place, downloaded: UIImage?) -> SkylinePhoto? {
        if let key = key(for: place), UIImage(named: "Skyline-\(key)") != nil {
            return UIImage(named: "Skyline-\(key)-night").map {
                SkylinePhoto(id: "b:" + key + "-night", image: $0, night: true, focus: byKey[key]?.night?.focus)
            }
        }
        return downloaded.map { SkylinePhoto(id: "d:" + slug(for: place) + "-night", image: $0, night: true) }
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

    /// The card's photo at a moment: by day its day photo (bundled, else downloaded); after dark its
    /// night photo when it has one. Until then (no bundled night photo, or the night search still
    /// running) the day photo stays, darkened for night, so the photo always fills the card, as the
    /// widget's. Only a downloaded city whose night search has finished with nothing
    /// (`nightSearched`) draws its skyline on the night sky. nil to draw one.
    static func photo(for place: Place, at date: Date, downloaded: UIImage?, downloadedNight: UIImage?,
                      nightSearched: Bool = false) -> SkylinePhoto? {
        guard let day = photo(for: place, downloaded: downloaded) else { return nil }
        guard wantsNight(place, at: date) else { return day }
        if let night = nightPhoto(for: place, downloaded: downloadedNight) { return night }
        return day.id.hasPrefix("d:") && nightSearched ? nil : day
    }

    /// A file-safe name for a card's downloaded photo: its city and time zone.
    static func slug(for place: Place) -> String {
        let raw = normalize(place.name) + "_" + place.timeZoneID.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        return String(raw.map { allowed.contains($0) ? $0 : "-" })
    }

    // MARK: Credits

    /// The four photos from before the manifest.
    private static let legacyCredits: [PhotoCreditItem] = [
        ("San Francisco", "San Francisco skyline from Coit Tower", "San_Francisco_skyline_from_Coit_Tower.jpg"),
        ("New York", "Manhattan from Weehawken, NJ", "Manhattan_from_Weehawken,_NJ.jpg"),
        ("London", "London Skyline (125508655)", "London_Skyline_(125508655).jpeg"),
        ("Tokyo", "Skyscrapers of Shinjuku 2009 January", "Skyscrapers_of_Shinjuku_2009_January.jpg"),
    ].map { city, title, file in
        PhotoCreditItem(id: "b:" + city, city: city, author: nil, license: nil,
                        source: URL(string: "https://commons.wikimedia.org/wiki/File:" + file), fallback: title)
    }

    /// The bundled photos' credits (day, and night where there is one), A to Z by city.
    static var bundledCredits: [PhotoCreditItem] {
        guard let manifest else { return legacyCredits }
        var seen = Set<String>()
        return manifest.flatMap { entry -> [PhotoCreditItem] in
            guard seen.insert(entry.key).inserted else { return [] }
            let city = entry.names.first ?? entry.key
            var items = [PhotoCreditItem(id: "b:" + entry.key, city: city, author: entry.credit?.author,
                                         license: entry.credit?.license,
                                         source: entry.credit?.source.flatMap { URL(string: $0) },
                                         fallback: entry.file)]
            if let night = entry.night, night.file != nil || night.credit != nil {
                items.append(PhotoCreditItem(id: "b:" + entry.key + "-night", city: city + ", night",
                                             author: night.credit?.author, license: night.credit?.license,
                                             source: night.credit?.source.flatMap { URL(string: $0) },
                                             fallback: night.file))
            }
            return items
        }
        .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    // MARK: Layout

    /// Where a photo's skyline sits when the manifest doesn't say (downloaded photos, old manifests).
    static let defaultFocus = 0.62

    /// The photo's frame in a card of `box`: scaled just enough to cover it (aspect-fill, no
    /// further zoom), centred across, and moved up or down so the point `focus` of the way down
    /// the photo sits at the card's vertical centre, clamped so the photo still covers the card.
    static func photoRect(image: CGSize, in box: CGSize, focus: Double?) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else {
            return CGRect(origin: .zero, size: box)
        }
        let scale = max(box.width / image.width, box.height / image.height)
        let w = image.width * scale, h = image.height * scale
        let f = CGFloat(focus ?? defaultFocus)
        let y = min(max(box.height / 2 - f * h, box.height - h), 0)
        return CGRect(x: (box.width - w) / 2, y: y, width: w, height: h)
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

    /// The Wikipedia titles to try for a city without a bundled photo: "City, Country" first
    /// (from the city list), then the plain name. None for UTC and offsets.
    static func wikipediaTitles(for place: Place) -> [String] {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = name.uppercased()
        guard !name.isEmpty, !upper.hasPrefix("UTC"), !upper.hasPrefix("GMT") else { return [] }
        var out: [String] = []
        func add(_ title: String?) {
            guard let title, !title.isEmpty, !out.contains(title) else { return }
            out.append(title)
        }
        let zoneRegions: Set<String> = ["America", "Europe", "Asia", "Africa", "Australia", "Pacific",
                                        "Atlantic", "Indian", "Antarctica", "Arctic", "Coordinated Universal Time"]
        let entry = CityDirectory.all.first {
            $0.timeZoneID == place.timeZoneID && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if let region = entry?.region, !region.isEmpty, !zoneRegions.contains(region) { add("\(name), \(region)") }
        if let code = place.countryCode ?? entry?.countryCode,
           let country = Locale(identifier: "en_US").localizedString(forRegionCode: code) {
            add("\(name), \(country)")
        }
        if let country = WorkWeek.countryName(zoneID: place.timeZoneID) { add("\(name), \(country)") }
        add(name)
        return out
    }
}

/// What a downloaded photo's credit file holds: the city, when it was asked for, the image file
/// (nil when there was no photo it could use), and the credit.
struct CityPhotoRecord: Codable {
    var name: String
    var fetched: Date
    var file: String?
    var credit: SkylinePhotoCredit?
}

/// Photos for cities without a bundled one, from Wikimedia Commons: asked for once (only the
/// city's name is sent), kept in Caches, and never asked for again within 30 days. Never blocks
/// the UI; the drawn skyline shows until a photo is ready, and offline nothing changes.
@MainActor
final class CityPhotos: ObservableObject {
    static let shared = CityPhotos()

    nonisolated static let enabledKey = "downloadCityPhotos"
    nonisolated static let userAgent = "Meridian/2.0 (https://bradcowdrey.com/meridian)"
    nonisolated static let retryAfter: TimeInterval = 30 * 24 * 3600

    /// Settings → Cities → Download City Photos (on unless turned off).
    nonisolated static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Loaded photos, by slug.
    @Published private(set) var images: [String: UIImage] = [:]
    /// What's on disk, by slug.
    @Published private(set) var records: [String: CityPhotoRecord] = [:]
    private var inFlight = Set<String>()
    /// Asked for (or failed offline) since launch: not again until the next launch.
    private var tried = Set<String>()
    private var recordsTask: Task<Void, Never>?

    private init() {
        recordsTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { CityPhotos.readRecords() }.value
            guard let self else { return }
            for (slug, record) in found where self.records[slug] == nil { self.records[slug] = record }
        }
    }

    /// A night photo's slug: its city's, with this after it (no time zone ends in it).
    nonisolated static let nightSuffix = ".night"

    /// The card's downloaded day photo, if it has been loaded.
    func image(for place: Place) -> UIImage? {
        images[SkylineArt.slug(for: place)]
    }

    /// The card's downloaded night photo, if there is one and it has been loaded.
    func nightImage(for place: Place) -> UIImage? {
        images[SkylineArt.slug(for: place) + Self.nightSuffix]
    }

    /// Whether the card's night search has finished, this launch, without a night photo.
    func nightSearched(for place: Place) -> Bool {
        let slug = SkylineArt.slug(for: place) + Self.nightSuffix
        return images[slug] == nil && tried.contains(slug)
    }

    /// Downloaded photos' credits (day and night), A to Z by city.
    var credits: [PhotoCreditItem] {
        records.compactMap { (slug, record) -> PhotoCreditItem? in
            guard record.file != nil else { return nil }
            let city = slug.hasSuffix(Self.nightSuffix) ? record.name + ", night" : record.name
            return PhotoCreditItem(id: "d:" + slug, city: city, author: record.credit?.author,
                                   license: record.credit?.license,
                                   source: record.credit?.source.flatMap { URL(string: $0) }, fallback: nil)
        }
        .sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }

    /// Loads the card's photos from disk, or asks Wikimedia for them (once), in the background:
    /// the day photo, then (once there is one) a night photo; after dark there, the night photo first.
    func request(_ place: Place) {
        guard Self.enabled, SkylineArt.bundledPhoto(for: place) == nil else { return }
        let slug = SkylineArt.slug(for: place)
        guard images[slug] == nil, !inFlight.contains(slug), !tried.contains(slug) else { return }
        inFlight.insert(slug)
        Task { [weak self] in
            await self?.load(slug: slug, place: place)
        }
    }

    private func load(slug: String, place: Place) async {
        defer {
            inFlight.remove(slug)
            tried.insert(slug)
        }
        _ = await recordsTask?.value
        if SkylineArt.wantsNight(place, at: Date()) {
            // After dark the night photo is the one shown: get it first.
            await loadNight(slug: slug + Self.nightSuffix, place: place)
            _ = await loadDay(slug: slug, place: place)
        } else {
            guard await loadDay(slug: slug, place: place) else { return }
            await loadNight(slug: slug + Self.nightSuffix, place: place)
        }
    }

    /// What's on disk for a slug: true once its image is loaded; false when there is nothing to
    /// load and it was asked for within 30 days (don't ask again); nil to ask Wikimedia.
    private func loadFromDisk(_ slug: String) async -> Bool? {
        guard let record = records[slug] else { return nil }
        if let file = record.file {
            if let image = await Self.readImage(file) {
                images[slug] = image
                return true
            }
            // The system cleared the image: ask again, but not within 30 days of the last fetch.
            return Date().timeIntervalSince(record.fetched) < Self.retryAfter ? false : nil
        }
        return Date().timeIntervalSince(record.fetched) < Self.retryAfter ? false : nil
    }

    /// Keeps what a fetch found (or that it found nothing) for a slug. True if there is a photo.
    private func keep(_ result: Fetch, slug: String, name: String) async -> Bool {
        switch result {
        case .offline:
            return false
        case .noPhoto:
            let record = CityPhotoRecord(name: name, fetched: Date(), file: nil, credit: nil)
            records[slug] = record
            await Self.write(record, slug: slug, data: nil)
            return false
        case .photo(let data, let credit):
            guard let image = await Self.decode(data) else {
                let record = CityPhotoRecord(name: name, fetched: Date(), file: nil, credit: nil)
                records[slug] = record
                await Self.write(record, slug: slug, data: nil)
                return false
            }
            let record = CityPhotoRecord(name: name, fetched: Date(), file: slug + ".jpg", credit: credit)
            await Self.write(record, slug: slug, data: data)
            records[slug] = record
            images[slug] = image
            return true
        }
    }

    /// The day photo: the city's Wikipedia lead image. True if the card has one.
    private func loadDay(slug: String, place: Place) async -> Bool {
        if images[slug] != nil { return true }
        if let found = await loadFromDisk(slug) { return found }
        guard Self.enabled else { return false }
        // The city list is large: look the city up off the main thread.
        let titles = await Task.detached(priority: .utility) { SkylineArt.wikipediaTitles(for: place) }.value
        guard !titles.isEmpty else { return false }
        return await keep(Self.fetch(titles: titles), slug: slug, name: place.name)
    }

    /// One night photo: a Commons search for "<city> skyline night", checked by its pixels. Without
    /// one, the card draws its skyline on the night sky after dark.
    private func loadNight(slug: String, place: Place) async {
        guard images[slug] == nil else { return }
        if let found = await loadFromDisk(slug) {
            // Searched within 30 days and nothing found: done.
            if !found { tried.insert(slug) }
            return
        }
        guard Self.enabled else { return }
        let result = await Self.fetchNight(city: place.name)
        let offline: Bool
        if case .offline = result { offline = true } else { offline = false }
        let found = await keep(result, slug: slug, name: place.name)
        // Finished without a photo (not offline): the card may draw its night sky.
        if !found && !offline { tried.insert(slug) }
    }

    // MARK: Disk

    nonisolated private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("CityPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func readRecords() -> [String: CityPhotoRecord] {
        guard let dir = directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [:] }
        var out: [String: CityPhotoRecord] = [:]
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let record = try? decoder.decode(CityPhotoRecord.self, from: data) {
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

    nonisolated private static func write(_ record: CityPhotoRecord, slug: String, data: Data?) async {
        await Task.detached(priority: .utility) {
            guard let dir = directory() else { return }
            if let data, let file = record.file {
                try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
            }
            if let json = try? JSONEncoder().encode(record) {
                try? json.write(to: dir.appendingPathComponent(slug + ".json"), options: .atomic)
            }
        }.value
    }

    // MARK: Network

    private enum Fetch {
        case photo(Data, SkylinePhotoCredit)
        /// No article, no photo, or no licence it may use: draw one (and ask again in 30 days).
        case noPhoto
        /// Offline, or Wikimedia was busy: try again next launch.
        case offline
    }

    private struct Summary: Decodable {
        struct Image: Decodable {
            let source: String
            var width: Int?
        }
        struct Coordinates: Decodable { var lat: Double? }
        var type: String?
        var coordinates: Coordinates?
        var thumbnail: Image?
        var originalimage: Image?
    }

    /// A failure worth asking again about on the next launch (no connection, timeout, rate limit,
    /// server trouble); any other client error is recorded like a city without a photo.
    nonisolated private static func transient(_ status: Int) -> Bool {
        status == 0 || status == 408 || status == 429 || status >= 500
    }

    nonisolated private static func fetch(titles: [String]) async -> Fetch {
        do {
            for title in titles {
                guard let url = summaryURL(title) else { continue }
                let (data, status) = try await get(url)
                if status == 404 || status == 400 { continue }
                guard status == 200 else { return transient(status) ? .offline : .noPhoto }
                // A place's article (it has coordinates), not a list of meanings.
                guard let summary = try? JSONDecoder().decode(Summary.self, from: data),
                      summary.type != "disambiguation", summary.coordinates != nil else { continue }
                guard let found = photo(summary), let metaURL = commonsURL(found.file) else { return .noPhoto }
                let (meta, metaStatus) = try await get(metaURL)
                guard metaStatus == 200 else { return transient(metaStatus) ? .offline : .noPhoto }
                guard let credit = credit(meta, file: found.file), isAllowed(credit.license) else { return .noPhoto }
                let (image, imageStatus) = try await get(found.url)
                if imageStatus == 404 { return .noPhoto }
                guard imageStatus == 200, !image.isEmpty else { return transient(imageStatus) ? .offline : .noPhoto }
                return .photo(image, credit)
            }
            return .noPhoto
        } catch {
            return .offline
        }
    }

    nonisolated private static func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(userAgent, forHTTPHeaderField: "Api-User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    nonisolated private static let titleCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~,()'_!*")

    nonisolated private static func summaryURL(_ title: String) -> URL? {
        let underscored = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = underscored.addingPercentEncoding(withAllowedCharacters: titleCharacters) else { return nil }
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/" + encoded)
    }

    /// The photo to download (about 1000 px wide) and its file name on Commons; nil when the
    /// article's image isn't on Commons (local files are usually not free) or is a drawing.
    nonisolated private static func photo(_ summary: Summary) -> (url: URL, file: String)? {
        guard let original = summary.originalimage ?? summary.thumbnail,
              original.source.contains("/wikipedia/commons/"),
              let originalURL = URL(string: original.source) else { return nil }
        let lower = original.source.lowercased()
        guard !lower.hasSuffix(".svg"), !lower.hasSuffix(".gif") else { return nil }
        // The file name: after /commons/a/ab/, or after /commons/thumb/a/ab/ in a thumbnail.
        let parts = originalURL.pathComponents
        let file: String
        if let thumb = parts.firstIndex(of: "thumb"), thumb + 3 < parts.count {
            file = parts[thumb + 3]
        } else if let last = parts.last {
            file = last
        } else { return nil }
        guard !file.isEmpty, file != "/" else { return nil }

        // Commons thumbnails come in set widths; 960 is the one near 1000.
        if let thumbnail = summary.thumbnail, thumbnail.source.contains("/thumb/"),
           (summary.originalimage?.width ?? 0) > 960,
           var components = URLComponents(string: thumbnail.source) {
            var path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if let last = path.last, let range = last.range(of: #"^\d+px-"#, options: .regularExpression) {
                path[path.count - 1] = last.replacingCharacters(in: range, with: "960px-")
                components.percentEncodedPath = path.joined(separator: "/")
                if let url = components.url { return (url, file) }
            }
        }
        // Small enough already (or no thumbnail): the original, if it isn't huge.
        if (summary.originalimage?.width ?? 0) <= 1600 { return (originalURL, file) }
        return nil
    }

    nonisolated private static func commonsURL(_ file: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: "File:" + file),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "extmetadata"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]
        // "+" in a file name would read as a space.
        if let query = components?.percentEncodedQuery {
            components?.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        return components?.url
    }

    /// The author, licence and links from Commons' extmetadata.
    nonisolated private static func credit(_ data: Data, file: String) -> SkylinePhotoCredit? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let page = pages.values.first as? [String: Any],
              let info = (page["imageinfo"] as? [[String: Any]])?.first,
              let meta = info["extmetadata"] as? [String: Any]
        else { return nil }
        return credit(meta: meta, file: file)
    }

    /// The author, licence and links from one file's extmetadata.
    nonisolated private static func credit(meta: [String: Any], file: String) -> SkylinePhotoCredit? {
        func value(_ key: String) -> String? {
            guard let raw = (meta[key] as? [String: Any])?["value"] as? String else { return nil }
            let text = plainText(raw)
            return text.isEmpty ? nil : text
        }
        guard let license = value("LicenseShortName") else { return nil }
        let pageURL = "https://commons.wikimedia.org/wiki/File:" + file.replacingOccurrences(of: " ", with: "_")
        let source = pageURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageURL
        return SkylinePhotoCredit(author: value("Artist") ?? value("Credit"), license: license,
                                  licenseUrl: value("LicenseUrl"), source: source)
    }

    /// HTML from Commons as plain text.
    nonisolated private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                               ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Night photos

    /// A night photo is dark overall: mean linear luminance at most this on a 330 px thumbnail.
    nonisolated static let nightMaxLuminance = 0.10
    /// Thumbnails checked per city at most.
    nonisolated private static let nightProbes = 4

    private struct NightCandidate {
        let title: String
        let url: URL
        let probe: URL
        let credit: SkylinePhotoCredit
    }

    /// The Commons search for a city's night skyline: landscape JPEG files, each with a ~960 px
    /// copy and its licence.
    nonisolated private static func nightSearchURL(_ city: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: city + " skyline night"),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "12"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|size|mime|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "960"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]
        if let query = components?.percentEncodedQuery {
            components?.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        return components?.url
    }

    /// The search's files in its order whose title names the city and whose licence it may use.
    nonisolated private static func nightCandidates(_ data: Data, city: String) -> [NightCandidate] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any]
        else { return [] }
        let wanted = SkylineArt.normalize(city)
        guard !wanted.isEmpty else { return [] }
        var found: [(order: Int, candidate: NightCandidate)] = []
        for value in pages.values {
            guard let page = value as? [String: Any],
                  let title = page["title"] as? String,
                  let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  (info["mime"] as? String) == "image/jpeg",
                  let width = info["width"] as? Int, let height = info["height"] as? Int,
                  width >= 800, width > height,
                  let meta = info["extmetadata"] as? [String: Any]
            else { continue }
            let file = title.hasPrefix("File:") ? String(title.dropFirst(5)) : title
            guard SkylineArt.normalize(file.replacingOccurrences(of: "_", with: " ")).contains(wanted),
                  let credit = credit(meta: meta, file: file), isAllowed(credit.license) else { continue }
            // The ~960 px copy (Commons gives the original when it is smaller), never a huge original.
            let thumb = info["thumburl"] as? String
            guard let full = thumb ?? (width <= 1600 ? info["url"] as? String : nil),
                  let url = URL(string: full) else { continue }
            let probeString = full.replacingOccurrences(of: #"/\d+px-"#, with: "/330px-", options: .regularExpression)
            let probe = URL(string: probeString) ?? url
            found.append((page["index"] as? Int ?? Int.max, NightCandidate(title: file, url: url, probe: probe, credit: credit)))
        }
        return found.sorted { $0.order < $1.order }.map(\.candidate)
    }

    /// An image's mean linear luminance (0 to 1), from a small copy.
    nonisolated static func meanLuminance(_ data: Data) -> Double? {
        guard let image = UIImage(data: data)?.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = 66, h = 33
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var total = 0.0
        for i in 0..<(w * h) {
            total += 0.2126 * linear(px[i * 4]) + 0.7152 * linear(px[i * 4 + 1]) + 0.0722 * linear(px[i * 4 + 2])
        }
        return total / Double(w * h)
    }

    /// One night photo for a city: the first search result that names the city, carries a licence
    /// it may use, and is dark on its 330 px thumbnail (a lit skyline, not a dusk or day shot).
    nonisolated private static func fetchNight(city: String) async -> Fetch {
        guard let url = nightSearchURL(city) else { return .noPhoto }
        do {
            let (data, status) = try await get(url)
            guard status == 200 else { return transient(status) ? .offline : .noPhoto }
            var probes = 0
            for candidate in nightCandidates(data, city: city) {
                guard probes < nightProbes else { break }
                probes += 1
                let (thumb, thumbStatus) = try await get(candidate.probe)
                if transient(thumbStatus) { return .offline }
                guard thumbStatus == 200, let mean = meanLuminance(thumb), mean <= nightMaxLuminance else { continue }
                let (image, imageStatus) = try await get(candidate.url)
                guard imageStatus == 200, !image.isEmpty else { return transient(imageStatus) ? .offline : .noPhoto }
                return .photo(image, candidate.credit)
            }
            return .noPhoto
        } catch {
            return .offline
        }
    }

    /// CC0, public domain, CC BY or CC BY-SA (any version); never NC or ND.
    nonisolated static func isAllowed(_ license: String?) -> Bool {
        guard let license else { return false }
        let l = license.lowercased().replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("cc0") || l.hasPrefix("public domain") || l == "pd" || l.hasPrefix("pd ") { return true }
        if l.contains(" nc") || l.contains(" nd") { return false }
        if l == "cc by" || l == "cc by sa" { return true }
        return l.range(of: #"^cc by( sa)? \d"#, options: .regularExpression) != nil
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

    /// skylines.json's "focus" (how far down the photo its skyline band sits, 0…1) by photo id:
    /// "b:<key>" for a day photo, "b:<key>-night" for a night one. Downloaded photos have none.
    nonisolated private static let bundledFocus: [String: Double] = {
        struct Night: Decodable { var focus: Double? }
        struct Item: Decodable {
            var key: String?
            var focus: Double?
            var night: Night?
        }
        struct Lenient: Decodable {
            let item: Item?
            init(from decoder: Decoder) throws { item = try? Item(from: decoder) }
        }
        guard let url = Bundle.main.url(forResource: "skylines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Lenient].self, from: data) else { return [:] }
        var out: [String: Double] = [:]
        for case let item? in list.map(\.item) {
            guard let key = item.key else { continue }
            if let f = item.focus { out["b:" + key] = f }
            if let f = item.night?.focus { out["b:" + key + "-night"] = f }
        }
        return out
    }()

    /// The bundled photo's skyline focus for a SkylinePhoto id, or nil (downloaded, or not measured).
    nonisolated static func focus(forID id: String) -> Double? { bundledFocus[id] }

    private static var task: Task<Void, Never>?
    /// The cities the large widget shows, whose downloaded photos are asked for even off screen.
    private static let widgetCities = 5

    static func sync(_ places: [Place], downloads: Bool) {
        // Screenshot mode never writes to the shared folder: the in-app widget previews read the
        // bundled photos straight from the app instead.
        if Screenshots.isActive {
            WidgetSkylines.inAppImage = { c in
                SkylineArt.photo(for: Place(name: c.name, timeZoneID: c.timeZoneID), downloaded: nil)?.image.cgImage
            }
            WidgetSkylines.inAppNightImage = { c in
                SkylineArt.nightPhoto(for: Place(name: c.name, timeZoneID: c.timeZoneID), downloaded: nil)?.image.cgImage
            }
            WidgetSkylines.inAppFocus = { c, night in
                let place = Place(name: c.name, timeZoneID: c.timeZoneID)
                let shown = night ? SkylineArt.nightPhoto(for: place, downloaded: nil) : SkylineArt.photo(for: place, downloaded: nil)
                return shown.flatMap { WidgetPhotoExport.focus(forID: $0.id) }
            }
            return
        }
        guard let dir = WidgetSkylines.directory else { return }
        var jobs: [Job] = []
        var ids = Set<String>()
        // Cities whose downloaded photo hasn't loaded yet: their widget copies are kept meanwhile.
        var pending = Set<String>()
        for (i, place) in places.enumerated() {
            let id = WidgetSkylines.id(name: place.name, timeZoneID: place.timeZoneID)
            guard ids.insert(id).inserted else { continue }
            if downloads && i < widgetCities { CityPhotos.shared.request(place) }
            let downloaded = downloads ? CityPhotos.shared.image(for: place) : nil
            guard let photo = SkylineArt.photo(for: place, downloaded: downloaded) else {
                if downloads, SkylineArt.key(for: place) == nil { pending.insert(id) }
                continue
            }
            let slug = SkylineArt.slug(for: place)
            let night = SkylineArt.nightPhoto(for: place, downloaded: downloads ? CityPhotos.shared.nightImage(for: place) : nil)
            var entry = WidgetSkylines.Entry(file: slug + ".jpg", source: photo.id, focus: focus(forID: photo.id))
            if let night {
                entry.night = slug + "-night.jpg"
                jobs.append(Job(id: nightID(id), entry: WidgetSkylines.Entry(file: slug + "-night.jpg", source: night.id,
                                                                            focus: focus(forID: night.id)),
                                image: night.image))
            }
            jobs.append(Job(id: id, entry: entry, image: photo.image))
        }
        let previous = task
        previous?.cancel()
        task = Task.detached(priority: .utility) {
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            if write(jobs, pending: pending, dir: dir) {
                await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }

    /// Writes the photos that changed and the index; removes photos no city uses. True if anything changed.
    /// Cities in `pending` keep their earlier downloaded copy until their photo has loaded.
    nonisolated private static func write(_ jobs: [Job], pending: Set<String>, dir: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = WidgetSkylines.readIndex()
        var index: [String: WidgetSkylines.Entry] = [:]
        var changed = false
        // Night photos first, so a city's entry names its night file only once that file is written.
        for job in jobs.sorted(by: { $0.id.hasSuffix("|night") && !$1.id.hasSuffix("|night") }) {
            let url = dir.appendingPathComponent(job.entry.file)
            var entry = job.entry
            if entry.night != nil, index[nightID(job.id)] == nil { entry.night = nil }
            // The same photo already there (its entry may still change, by its night file).
            if let previous = old[job.id], previous.file == entry.file, previous.source == entry.source,
               fm.fileExists(atPath: url.path) {
                index[job.id] = entry
                continue
            }
            guard let data = jpeg(job.image) else { continue }
            if (try? data.write(to: url, options: .atomic)) != nil {
                index[job.id] = entry
                changed = true
            }
        }
        for id in pending {
            for key in [id, nightID(id)] where index[key] == nil {
                if let entry = old[key], entry.source.hasPrefix("d:"),
                   fm.fileExists(atPath: dir.appendingPathComponent(entry.file).path) {
                    index[key] = entry
                }
            }
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

    /// The photo filling 600×300 (cropped from its centre, as the cards crop it), JPEG at 0.6.
    nonisolated private static func jpeg(_ image: UIImage) -> Data? {
        let size = CGSize(width: 600, height: 300)
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = max(size.width / iw, size.height / ih)
        let w = iw * scale, h = ih * scale
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.6) { _ in
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
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
            // Filling the card, its skyline band (the photo's focus) at the card's centre.
            let rect = SkylineArt.photoRect(image: photo.image.size, in: size, focus: photo.focus)
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
    /// origin); `size` is the card's.
    static func isBright(photo: SkylinePhoto?, seed: String, phase: Sky.Phase, size: CGSize, region: CGRect) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        let area = region.isNull ? CGRect.zero : region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !area.isNull, area.width > 0.001, area.height > 0.001 else { return false }
        // A twentieth of the card is close enough for the area, a quarter for a photo's shape.
        func q(_ v: CGFloat) -> Int { Int((v * 20).rounded()) }
        let areaKey = "\(q(area.minX)),\(q(area.minY)),\(q(area.width)),\(q(area.height))"
        let key: String
        if let photo {
            let aspect = (size.width / size.height * 4).rounded() / 4
            key = "photo|\(photo.id)|\(phase)|\(aspect)|\(areaKey)"
        } else {
            key = "drawn|\(seed)|\(phase)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))|\(areaKey)"
        }
        if let hit = cache[key] { return hit }
        if cache.count > 300 { cache.removeAll() }

        let luminance: Double?
        if let photo {
            luminance = photoLuminance(photo.image, focus: photo.focus, phase: SkylineArt.tintPhase(phase, photo: photo),
                                       size: size, region: area)
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
    /// its focus at the card's centre), drawn into a small bitmap, then saturated and tinted as the
    /// card shades it, darkened by the scrim, and averaged.
    private static func photoLuminance(_ photo: UIImage, focus: Double?, phase: Sky.Phase, size: CGSize,
                                       region: CGRect) -> Double? {
        guard let cg = photo.cgImage else { return nil }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        guard iw > 0, ih > 0 else { return nil }
        // The card's frame in the photo's pixels (the inverse of the photo's frame in the card).
        let rect = SkylineArt.photoRect(image: CGSize(width: iw, height: ih), in: size, focus: focus)
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

/// Settings → About → Photo Credits: where the skyline photos come from, built in and downloaded,
/// with each one's author, licence and a link to it on Wikimedia Commons.
struct PhotoCreditsView: View {
    @ObservedObject private var photos = CityPhotos.shared

    var body: some View {
        let downloaded = photos.credits
        Form {
            Section {
                ForEach(SkylineArt.bundledCredits) { credit in creditRow(credit) }
            } header: {
                caption("Built In")
            } footer: {
                caption("Skyline photos from Wikimedia Commons. Tap one to see it there. Cities without a photo show a skyline drawn by Meridian.")
            }
            .meridianSection()
            if !downloaded.isEmpty {
                Section {
                    ForEach(downloaded) { credit in creditRow(credit) }
                } header: {
                    caption("Downloaded")
                } footer: {
                    caption("Downloaded once from Wikimedia Commons and kept on your iPhone.")
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
        let line = [credit.author, credit.license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(credit.city).foregroundStyle(.white)
            Text(line.isEmpty ? (credit.fallback ?? "Wikimedia Commons") : line)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .lineLimit(2)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            .textCase(nil)
    }
}
