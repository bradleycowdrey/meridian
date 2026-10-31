import Foundation

/// A city the user tracks.
struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// The "My Location" row (see MyLocation) has this fixed id.
    static let myLocationID = UUID(uuidString: "6D7E1A2B-4C3D-4E5F-8A9B-0C1D2E3F4A5B")!
    var isMyLocation: Bool { id == Self.myLocationID }

    /// Three-letter tag used in the menu bar, e.g. "LON".
    var tag: String {
        String(name.filter(\.isLetter).prefix(3)).uppercased()
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "UTC+5:30", "UTC−4", "UTC".
    func offsetLabel(at date: Date) -> String {
        TimeMath.offsetLabel(seconds: timeZone.secondsFromGMT(for: date))
    }
}

enum TimeMath {
    /// DateFormatters are slow to make, and these run on every frame of a drag, so each
    /// format-and-zone pair is made once.
    private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        formattersLock.lock(); defer { formattersLock.unlock() }
        let key = "\(format)|\(zone.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }

    static func offsetLabel(seconds: Int) -> String {
        if seconds == 0 { return "UTC" }
        let sign = seconds > 0 ? "+" : "−"
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    /// Start of the current hour on the user's own clock.
    static func hourAnchor(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// "14:05" or "2:05 PM", with a thin space before AM/PM (as everywhere in Meridian).
    static func time(_ date: Date, in zone: TimeZone, use24h: Bool) -> String {
        formatter(use24h ? "HH:mm" : "h:mm\u{2009}a", zone).string(from: date)
    }

    static func weekday(_ date: Date, in zone: TimeZone) -> String {
        formatter("EEE", zone).string(from: date)
    }

    static func fullMoment(_ date: Date, in zone: TimeZone, use24h: Bool) -> String {
        formatter(use24h ? "EEE d MMM, HH:mm" : "EEE d MMM, h:mm\u{2009}a", zone).string(from: date)
    }

    /// Calendar-day difference between a zone and the user's zone at a moment: -1, 0 or +1.
    static func dayShift(_ date: Date, zone: TimeZone) -> Int {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let a = there.dateComponents([.year, .month, .day], from: date)
        let b = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let da = there.date(from: a), let db = there.date(from: b) else { return 0 }
        return Int((da.timeIntervalSince(db) / 86_400).rounded())
    }
}
