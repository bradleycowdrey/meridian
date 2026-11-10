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

/// The city photos bundled with the Mac app and its widget: Resources/Skylines/skyline_<key>.jpg
/// (day) and skyline_<key>_night.jpg, named by Resources/skylines.json. scripts/build-app.sh
/// copies them in; the app holds the full 1000 px photos and the widget, which is sandboxed, its
/// own 600 px copies. Without them (a bare `swift run`) every city shows the sky gradient.
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
    }

    private struct Entry: Decodable {
        let key: String
        var names: [String] = []
        var zone: String?
        var file: String?
        var credit: Credit?
        /// nil when the photo pipeline found no night photo for the city.
        var night: Night?

        private enum CodingKeys: String, CodingKey { case key, names, zone, file, credit, night }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
            zone = try? c.decodeIfPresent(String.self, forKey: .zone)
            file = try? c.decodeIfPresent(String.self, forKey: .file)
            credit = try? c.decodeIfPresent(Credit.self, forKey: .credit)
            night = try? c.decodeIfPresent(Night.self, forKey: .night)
        }
    }

    /// An entry that fails to decode is skipped rather than losing the whole manifest.
    private struct LenientEntry: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }

    /// skylines.json from the bundle; empty when it isn't there.
    private static let manifest: [Entry] = {
        guard let url = Bundle.main.url(forResource: "skylines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([LenientEntry].self, from: data)
        else { return [] }
        return list.compactMap { $0.entry }
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

    // MARK: Lookup

    private static let lock = NSLock()
    /// Answers so far, by name and zone ("" for none).
    private static var keyCache: [String: String] = [:]
    /// Decoded photos, by "<key>|<night>|<maxPixel>".
    private static var imageCache: [String: CGImage] = [:]
    private static let imageCacheLimit = 40

    /// The photo's key for a city (matched by name and time zone), or nil when the manifest has no
    /// such city or its day photo isn't in the bundle.
    static func key(name: String, timeZoneID: String) -> String? {
        let cacheKey = name + "|" + timeZoneID
        lock.lock()
        let hit = keyCache[cacheKey]
        lock.unlock()
        if let hit { return hit.isEmpty ? nil : hit }

        let candidates = index[normalize(name)] ?? []
        let exact = candidates.first(where: { $0.zone == timeZoneID })
        let match = exact ?? candidates.first(where: { zoneFits($0.zone, timeZoneID) })
        var result: String? = match?.key
        if let found = result, !files.contains(fileName(key: found, night: false)) { result = nil }

        lock.lock()
        if keyCache.count > 400 { keyCache.removeAll() }
        keyCache[cacheKey] = result ?? ""
        lock.unlock()
        return result
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
        let file = fileName(key: key, night: night)
        guard files.contains(file), let url = directory?.appendingPathComponent(file),
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

    /// Which photo a city shows: its night photo after dark when it has one, else its day photo
    /// (darkened after dark). nil when the city has no photo.
    fileprivate static func pick(name: String, timeZoneID: String, night: Bool) -> MacSkylinePick? {
        guard let key = key(name: name, timeZoneID: timeZoneID) else { return nil }
        guard night else { return MacSkylinePick(key: key, night: false, dimmed: false) }
        if files.contains(fileName(key: key, night: true)) {
            return MacSkylinePick(key: key, night: true, dimmed: false)
        }
        return MacSkylinePick(key: key, night: false, dimmed: true)
    }

    // MARK: Credits

    private static let creditList: [MacPhotoCredit] = {
        var seen = Set<String>()
        var out: [MacPhotoCredit] = []
        for entry in manifest {
            guard seen.insert(entry.key).inserted else { continue }
            let city = entry.names.first ?? entry.key
            out.append(MacPhotoCredit(id: entry.key, city: city, author: entry.credit?.author,
                                      license: entry.credit?.license,
                                      source: entry.credit?.source.flatMap { URL(string: $0) }))
            if let night = entry.night, night.file != nil || night.credit != nil {
                out.append(MacPhotoCredit(id: entry.key + "-night", city: city + ", night",
                                          author: night.credit?.author, license: night.credit?.license,
                                          source: night.credit?.source.flatMap { URL(string: $0) }))
            }
        }
        return out.sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
    }()

    /// The bundled photos' credits (day, and night where there is one), A to Z by city.
    static var credits: [MacPhotoCredit] { creditList }
}

/// The photo a backdrop shows: the city's key, whether it is the night photo, and whether a day
/// photo stands in after dark (then darkened).
fileprivate struct MacSkylinePick {
    let key: String
    let night: Bool
    let dimmed: Bool

    func id(maxPixel: Int) -> String { "\(key)|\(night)|\(maxPixel)|\(dimmed)" }
}

fileprivate func macSkylineTone(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// A photo filling its frame: scaled to cover it, centred sideways and, when cropped top and
/// bottom, held 35 % from the top (where skylines sit). With `focusX` (points from the frame's
/// leading edge) the photo's centre sits there instead, the photo scaled up just enough to still
/// cover the frame, and held 42 % from the top.
fileprivate struct MacSkylinePhoto: View {
    let image: CGImage
    let dimmed: Bool
    var focusX: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let iw = CGFloat(max(image.width, 1)), ih = CGFloat(max(image.height, 1))
            let centre: CGFloat = focusX.map { min(max($0, 0), geo.size.width) } ?? geo.size.width / 2
            let reach: CGFloat = 2 * max(centre, geo.size.width - centre)
            let scale: CGFloat = max(reach / iw, geo.size.height / ih)
            let w = iw * scale, h = ih * scale
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
                .offset(x: centre - w / 2, y: (geo.size.height - h) * (focusX == nil ? 0.35 : 0.42))
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
    private let focusX: CGFloat?

    private struct Shown {
        let id: String
        let image: CGImage
        let dimmed: Bool
    }

    @State private var shown: Shown?

    /// `synchronous` decodes in `body` (widgets and ImageRenderer, which never run tasks);
    /// otherwise the photo is decoded off the main thread and fades in. `focusX` (points from the
    /// leading edge) puts the photo's centre there rather than in the middle of the frame.
    init(name: String, timeZoneID: String, latitude: Double? = nil, longitude: Double? = nil,
         date: Date, maxPixel: Int = 1000, synchronous: Bool = false, focusX: CGFloat? = nil) {
        self.name = name
        self.timeZoneID = timeZoneID
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.maxPixel = maxPixel
        self.synchronous = synchronous
        self.focusX = focusX
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
                    MacSkylinePhoto(image: image, dimmed: pick.dimmed, focusX: focusX)
                }
            } else if let shown {
                MacSkylinePhoto(image: shown.image, dimmed: shown.dimmed, focusX: focusX)
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
                withTransaction(instant) { shown = Shown(id: wanted, image: ready, dimmed: pick.dimmed) }
                return
            }
            let key = pick.key, isNight = pick.night, size = maxPixel
            let image = await Task.detached(priority: .utility) {
                MacSkylines.image(key: key, night: isNight, maxPixel: size)
            }.value
            guard !Task.isCancelled else { return }
            shown = image.map { Shown(id: wanted, image: $0, dimmed: pick.dimmed) }
        }
    }
}

/// Settings → About → Photo Credits: every bundled photo's author, licence and source.
struct MacPhotoCreditsView: View {
    @Environment(\.dismiss) private var dismiss

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
            if credits.isEmpty {
                Text("No city photos in this copy of Meridian.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(credits) { credit in
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
            }
        }
        .frame(width: 420, height: 480)
        .preferredColorScheme(.dark)
    }

    /// "author · licence", or where the photo is from when neither is known.
    private static func detail(_ credit: MacPhotoCredit) -> String {
        let parts = [credit.author, credit.license].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Wikimedia Commons" : parts.joined(separator: " · ")
    }
}
#endif
