import SwiftUI
import ImageIO
import WidgetKit

/// Downloads the hosted AI plates (plates-remote.json "plates") that cities without a built-in
/// photo match by their town or metro: day and night once each, kept in MacSkylines.platesDirectory
/// (shared with the App Store build's widget), never asked for again once there. Only while
/// Settings → Cities → Download City Photos is on. The requests carry nothing but the image's
/// URL: no cookies, no cache, a plain user agent. A plate that fails offline (or with a server
/// error) is tried again next launch; one that isn't there (or isn't an image) only after 30 days
/// (MacSkylines.markPlateMissing), as on iPhone and Android. Meanwhile, and while the switch is
/// off, the city shows its default scene.
@MainActor
final class PlateDownloads: ObservableObject {
    static let shared = PlateDownloads()

    /// Settings → Cities → Download City Photos.
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            MacSkylines.setDownloadsEnabled(enabled)
            generation += 1
            WidgetCenter.shared.reloadAllTimelines()
            if enabled { pump() }
        }
    }

    /// Goes up each time a plate arrives (or the switch changes), so the rows look again.
    @Published private(set) var generation = 0

    private var queue: [MacSkylines.HostedPlate] = []
    private var queued: Set<String> = []
    /// Plates that failed this launch: not asked for again until the next one (one found missing
    /// not for 30 days, on disk).
    private var failed: Set<String> = []
    private var running = false

    private init() {
        enabled = MacSkylines.downloadsEnabled
        MacSkylines.syncDownloadsMarker()
    }

    /// Nothing but the request itself: no cookies, no credentials, no cache, no identifiers.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["User-Agent": "Meridian"]
        return URLSession(configuration: config)
    }()

    /// Asks for the plates these cities want and this Mac doesn't have (in the background, one
    /// at a time). Does nothing while Download City Photos is off.
    func request(_ places: [Place]) {
        for place in places {
            enqueue(name: place.name, timeZoneID: place.timeZoneID, latitude: place.latitude,
                    longitude: place.longitude, countryCode: place.countryCode)
        }
        pump()
    }

    /// The same for one city (a panel row).
    func request(name: String, timeZoneID: String, latitude: Double? = nil, longitude: Double? = nil,
                 countryCode: String? = nil) {
        enqueue(name: name, timeZoneID: timeZoneID, latitude: latitude, longitude: longitude,
                countryCode: countryCode)
        pump()
    }

    private func enqueue(name: String, timeZoneID: String, latitude: Double?, longitude: Double?,
                         countryCode: String?) {
        guard enabled,
              let plate = MacSkylines.plateToDownload(name: name, timeZoneID: timeZoneID, latitude: latitude,
                                                      longitude: longitude, countryCode: countryCode),
              !failed.contains(plate.key), MacSkylines.plateDue(key: plate.key),
              queued.insert(plate.key).inserted else { return }
        queue.append(plate)
    }

    private func pump() {
        guard !running, enabled, !queue.isEmpty else { return }
        running = true
        let plate = queue.removeFirst()
        Task {
            let outcome = await Self.fetch(plate)
            queued.remove(plate.key)
            switch outcome {
            case .stored:
                generation += 1
                WidgetCenter.shared.reloadAllTimelines()
            case .missing:
                failed.insert(plate.key)
                MacSkylines.markPlateMissing(key: plate.key)
            case .offline:
                failed.insert(plate.key)
            }
            running = false
            pump()
        }
    }

    /// How a plate's download ended: kept; not there (or not an image), not asked for again
    /// for 30 days; or offline / server trouble / not written, asked for again next launch.
    private enum Outcome: Sendable { case stored, missing, offline }

    /// One image's download: its JPEG, or why there is none.
    private enum Download: Sendable { case data(Data), missing, offline }

    /// Downloads both photos (the day one, then the night one) and keeps them; nothing is kept
    /// unless both arrive.
    private nonisolated static func fetch(_ plate: MacSkylines.HostedPlate) async -> Outcome {
        let day: Data, night: Data
        switch await image(plate.day) {
        case .data(let d): day = d
        case .missing: return .missing
        case .offline: return .offline
        }
        switch await image(plate.night) {
        case .data(let d): night = d
        case .missing: return .missing
        case .offline: return .offline
        }
        let stored = await Task.detached(priority: .utility) {
            MacSkylines.storePlate(key: plate.key, day: day, night: night)
        }.value
        return stored ? .stored : .offline
    }

    /// A failure worth asking again about on the next launch (no connection, timeout, rate limit,
    /// server trouble), as on iPhone; any other status is a plate that isn't there.
    private nonisolated static func transient(_ status: Int) -> Bool {
        status == 0 || status == 408 || status == 429 || status >= 500
    }

    /// One JPEG: HTTP 200, a sane size, and an image ImageIO can read.
    private nonisolated static func image(_ url: URL) async -> Download {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        guard let (data, response) = try? await session.data(for: request) else { return .offline }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return transient(status) ? .offline : .missing }
        guard data.count > 1_000, data.count < 8_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
        else { return .missing }
        return .data(data)
    }
}
