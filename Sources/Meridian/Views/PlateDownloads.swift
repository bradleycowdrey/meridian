import SwiftUI
import ImageIO
import WidgetKit

/// Downloads the hosted AI plates (plates-remote.json) for cities without a built-in photo: day
/// and night once each, kept in MacSkylines.platesDirectory (shared with the widget), never asked
/// for again once there. Only while Settings → Cities → Download City Photos is on. The requests
/// carry nothing but the image's URL: no cookies, no cache, a plain user agent. A plate that fails
/// (offline, missing) is tried again next launch; meanwhile the city keeps its sky, as before (the
/// Mac has no Wikimedia download to fall back to).
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
    /// Plates that failed this launch: not asked for again until the next one.
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
        for place in places { enqueue(name: place.name, timeZoneID: place.timeZoneID) }
        pump()
    }

    /// The same for one city (a panel row).
    func request(name: String, timeZoneID: String) {
        enqueue(name: name, timeZoneID: timeZoneID)
        pump()
    }

    private func enqueue(name: String, timeZoneID: String) {
        guard enabled, let plate = MacSkylines.plateToDownload(name: name, timeZoneID: timeZoneID),
              !failed.contains(plate.key), queued.insert(plate.key).inserted else { return }
        queue.append(plate)
    }

    private func pump() {
        guard !running, enabled, !queue.isEmpty else { return }
        running = true
        let plate = queue.removeFirst()
        Task {
            let ok = await Self.fetch(plate)
            queued.remove(plate.key)
            if ok {
                generation += 1
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                failed.insert(plate.key)
            }
            running = false
            pump()
        }
    }

    /// Downloads both photos and keeps them; false when either fails (nothing is kept then).
    private nonisolated static func fetch(_ plate: MacSkylines.HostedPlate) async -> Bool {
        guard let day = await image(plate.day), let night = await image(plate.night) else { return false }
        return await Task.detached(priority: .utility) {
            MacSkylines.storePlate(key: plate.key, day: day, night: night)
        }.value
    }

    /// One JPEG: HTTP 200, a sane size, and an image ImageIO can read; else nil.
    private nonisolated static func image(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1_000, data.count < 8_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
        else { return nil }
        return data
    }
}
