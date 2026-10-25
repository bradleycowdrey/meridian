import SwiftUI
import WidgetKit

// Shared by the Mac app, the iPhone app (ios/) and both widget extensions (Widget/MeridianWidget.swift),
// so this file stands alone: no Palette, Metrics or ZoneStore. The app writes a WidgetSnapshot whenever cities
// or clock settings change; the widget reads it and draws the same day/night tiles.

/// What the widget needs from the app: cities in order and the clock settings.
struct WidgetSnapshot: Codable, Equatable {
    struct City: Codable, Equatable {
        var name: String
        var timeZoneID: String
    }

    var cities: [City]
    var use24h: Bool

    #if os(iOS)
    /// iPhone: the App Group container the app and its widget share.
    static let appGroup = "group.com.bradcowdrey.meridian"
    static var fileURL: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("widget.json")
    }
    #else
    /// Mac: the widget is sandboxed, so this uses the real home folder rather than its container
    /// (its entitlements allow reading this one folder).
    static var fileURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Meridian/widget.json")
    }
    #endif

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }

    /// Writes the file only when something changed. Returns true if it did.
    @discardableResult
    func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // stable bytes, so unchanged data isn't rewritten
        guard let data = try? encoder.encode(self) else { return false }
        if (try? Data(contentsOf: Self.fileURL)) == data { return false }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: Self.fileURL, options: .atomic)) != nil
    }

    static var placeholder: WidgetSnapshot {
        let local = TimeZone.current.identifier
        let localName = local.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Here"
        var cities = [City(name: localName, timeZoneID: local)]
        for (name, id) in [("New York", "America/New_York"), ("London", "Europe/London"), ("Tokyo", "Asia/Tokyo")]
        where id != local {
            cities.append(City(name: name, timeZoneID: id))
        }
        return WidgetSnapshot(cities: cities, use24h: true)
    }
}

/// Sky through the day in bradcowdrey.com tones: warm black at night, warm greys at twilight,
/// cream in daylight.
enum DayColor {
    private static let stops: [(Double, UInt32)] = [
        (0, 0x161412),
        (5, 0x1A1816),
        (6.5, 0x4A4540),
        (8, 0xB0A898),
        (9.5, 0xE0D8D0),
        (12, 0xFFF1E5),
        (15, 0xFFF1E5),
        (17.5, 0xE0D8D0),
        (19, 0x807870),
        (20.5, 0x34302B),
        (22, 0x1C1A17),
        (24, 0x161412),
    ]

    static func style(at hour: Double) -> (fill: Color, text: Color) {
        let h = hour.truncatingRemainder(dividingBy: 24)
        var rgb = components(stops[0].1)
        for i in 0..<(stops.count - 1) where h >= stops[i].0 && h <= stops[i + 1].0 {
            let a = components(stops[i].1)
            let b = components(stops[i + 1].1)
            let span = stops[i + 1].0 - stops[i].0
            let t = span == 0 ? 0 : (h - stops[i].0) / span
            rgb = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            break
        }
        let luminance = 0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2
        let text = luminance > 0.55 ? WidgetTone.bg : WidgetTone.secondary
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), text)
    }

    fileprivate static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// The brand palette, restated here so the widget extension doesn't need the app's Palette.
enum WidgetTone {
    static let bg = tone(0x1A1816)
    static let primary = Color.white
    static let secondary = tone(0xE0D8D0)
    static let muted = tone(0xB0A898)
    static let faint = tone(0x807870)
    static let cream = tone(0xFFF1E5)
    static let crimson = tone(0x990F3D)

    private static func tone(_ hex: UInt32) -> Color {
        let c = DayColor.components(hex)
        return Color(red: c.0, green: c.1, blue: c.2)
    }
}

/// The widget face for each size: small shows one city, medium two side by side (each with its
/// hour before and after), large four with the hour before, now and the hour after.
struct WidgetClockView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily

    var body: some View {
        VStack(spacing: 0) {
            // The bradcowdrey.com crimson rule, full bleed across the top.
            WidgetTone.crimson.frame(height: 3)
            Group {
                if cities.isEmpty {
                    VStack(spacing: 6) {
                        Text("No cities yet")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add cities in Meridian")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTone.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                switch family {
                case .systemLarge: strip
                case .systemMedium:
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(cities.enumerated()), id: \.offset) { _, city in
                            cityCell(city, timeSize: 32).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if cities.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                default:
                    cityCell(cities[0], timeSize: 36)
                }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(WidgetTone.primary)
    }

    private var cityLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        default: return 4
        }
    }

    private var cities: [WidgetSnapshot.City] { Array(snapshot.cities.prefix(cityLimit)) }

    // MARK: Small and medium: one city, big, with its next hours

    private func cityCell(_ city: WidgetSnapshot.City, timeSize: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        return VStack(alignment: .leading, spacing: 2) {
            Text(city.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WidgetTone.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(clock)
                    .font(.system(size: timeSize, weight: .medium))
                    .monospacedDigit()
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetTone.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(relative(zone))
                .font(.system(size: 11))
                .foregroundStyle(WidgetTone.faint)
                .lineLimit(1)
            Spacer(minLength: 6)
            // The hour before, now (outlined) and the hour after.
            HStack(spacing: 4) {
                ForEach(-1...1, id: \.self) { k in
                    tile(anchor.addingTimeInterval(Double(k) * 3600), zone: zone)
                        .overlay {
                            if k == 0 {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(WidgetTone.cream, lineWidth: 1.5)
                            }
                        }
                }
            }
            .frame(height: 24)
        }
    }

    /// "Today, −5 h" style context under the city name.
    private func relative(_ zone: TimeZone) -> String {
        let diff = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        let day: String
        switch Self.dayShift(date, zone: zone) {
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        default: day = "Today"
        }
        if diff == 0 { return day }
        let sign = diff > 0 ? "+" : "−"
        let hours = abs(diff) / 3600
        let minutes = (abs(diff) % 3600) / 60
        return "\(day), \(sign)\(hours)\(minutes == 0 ? "" : ":\(String(format: "%02d", minutes))") h"
    }

    @ViewBuilder private func dayBadge(_ zone: TimeZone) -> some View {
        let shift = Self.dayShift(date, zone: zone)
        if shift != 0 {
            Text(shift > 0 ? "+\(shift)" : "−\(-shift)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetTone.muted)
        }
    }

    // MARK: Large: day/night tiles

    private let columns = 3

    private var strip: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            // Whole points, so tile and outline edges stay crisp.
            let pitch = ((geo.size.width * 0.52) / CGFloat(columns)).rounded(.down)
            let labelWidth = geo.size.width - pitch * CGFloat(columns)
            let headerHeight: CGFloat = 16
            let rows = max(cities.count, 1)
            let rowHeight = min(72, (geo.size.height - headerHeight - gap * CGFloat(rows)) / CGFloat(rows))
            let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
            let half = columns / 2

            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: 0) {
                    Text("Meridian")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTone.faint)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(-half...half, id: \.self) { k in
                        Text(k == 0 ? "Now" : (k > 0 ? "+\(k)" : "−\(-k)"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(k == 0 ? WidgetTone.cream : WidgetTone.faint)
                            .monospacedDigit()
                            .frame(width: pitch)
                    }
                }
                .frame(height: headerHeight)

                ForEach(Array(cities.enumerated()), id: \.offset) { _, city in
                    let zone = TimeZone(identifier: city.timeZoneID) ?? .current
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(city.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WidgetTone.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(Self.time(date, zone: zone, use24h: snapshot.use24h, compact: true))
                                    .font(.system(size: 24, weight: .medium))
                                    .monospacedDigit()
                                dayBadge(zone)
                            }
                            .lineLimit(1)
                        }
                        .frame(width: labelWidth - 6, alignment: .leading)
                        .padding(.trailing, 6)

                        ForEach(-half...half, id: \.self) { k in
                            tile(anchor.addingTimeInterval(Double(k) * 3600), zone: zone)
                                .frame(width: pitch - gap, height: rowHeight)
                                .frame(width: pitch)
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
            // The "now" column outline, through every row.
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WidgetTone.cream, lineWidth: 1.5)
                    .frame(width: pitch, height: CGFloat(cities.count) * (rowHeight + gap))
                    .offset(x: labelWidth + CGFloat(half) * pitch, y: headerHeight + gap / 2)
            }
        }
    }

    private func tile(_ moment: Date, zone: TimeZone) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: moment)
        let minute = calendar.component(.minute, from: moment)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        let newDay = !calendar.isDate(moment, inSameDayAs: moment.addingTimeInterval(-3600))
        let label: Text = {
            var text = snapshot.use24h ? Text(String(format: "%02d", hour)) : Text("\(hour % 12 == 0 ? 12 : hour % 12)")
            // Half-hour and 45-minute zones: "05:30" reads "05" + small ":30".
            if minute != 0 { text = text + Text(":\(String(format: "%02d", minute))").font(.system(size: 9, weight: .medium)) }
            if !snapshot.use24h { text = text + Text(hour < 12 ? "a" : "p").font(.system(size: 9, weight: .medium)) }
            return text
        }()
        return label
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(style.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(style.fill))
            .overlay(alignment: .leading) {
                // A new day starts at midnight.
                if newDay {
                    Capsule().fill(WidgetTone.crimson).frame(width: 2).padding(.vertical, 6).offset(x: -3)
                }
            }
    }

    // MARK: Helpers (the widget can't see the app's TimeMath)

    /// "14:05" and no suffix, or "2:05" and "PM".
    static func clock(_ date: Date, zone: TimeZone, use24h: Bool) -> (String, String?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
        if use24h { return (String(format: "%02d:%02d", hour, minute), nil) }
        return ("\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))", hour < 12 ? "AM" : "PM")
    }

    /// "14:05", "2:05 PM", or "2:05p" where space is tight.
    static func time(_ date: Date, zone: TimeZone, use24h: Bool, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = use24h ? "HH:mm" : (compact ? "h:mm" : "h:mm a")
        let text = formatter.string(from: date)
        guard !use24h, compact else { return text }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return text + (calendar.component(.hour, from: date) < 12 ? "a" : "p")
    }

    static func dayShift(_ date: Date, zone: TimeZone) -> Int {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let a = there.dateComponents([.year, .month, .day], from: date)
        let b = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let da = there.date(from: a), let db = there.date(from: b) else { return 0 }
        return Int((da.timeIntervalSince(db) / 86_400).rounded())
    }
}

#if os(iOS)
/// Lock Screen widgets: inline (above the clock), circular and rectangular. They follow the
/// Lock Screen's own tint, so they use plain text and shapes rather than the brand colours.
struct AccessoryClockView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily

    private func zone(_ city: WidgetSnapshot.City) -> TimeZone { TimeZone(identifier: city.timeZoneID) ?? .current }
    /// "SF" for San Francisco, "NY" for New York, "LON" for London.
    private func tag(_ city: WidgetSnapshot.City) -> String {
        let words = city.name.split(whereSeparator: { !$0.isLetter }).filter { !$0.isEmpty }
        if words.count > 1 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
        return String(city.name.filter(\.isLetter).prefix(3)).uppercased()
    }
    private func time(_ city: WidgetSnapshot.City) -> String {
        WidgetClockView.time(date, zone: zone(city), use24h: snapshot.use24h, compact: true)
    }
    private func shift(_ city: WidgetSnapshot.City) -> String {
        let d = WidgetClockView.dayShift(date, zone: zone(city))
        return d == 0 ? "" : (d > 0 ? " +\(d)" : " −\(-d)")
    }
    /// The first city that isn't the phone's own time zone, if any; otherwise the first city.
    private var featured: WidgetSnapshot.City? {
        snapshot.cities.first { zone($0).secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date) }
            ?? snapshot.cities.first
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line above the Lock Screen clock: "LON 14:05 · TYO 22:05".
            Text(snapshot.cities.filter { $0 != snapshot.cities.first || snapshot.cities.count == 1 }
                .prefix(2).map { "\(tag($0)) \(time($0))" }.joined(separator: " · "))
        case .accessoryCircular:
            if let city = featured {
                VStack(spacing: 0) {
                    Text(tag(city)).font(.system(size: 11, weight: .semibold))
                    Text(time(city)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(4)
            } else {
                Image(systemName: "globe")
            }
        default:
            // Rectangular: three cities, one per line.
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(snapshot.cities.prefix(3).enumerated()), id: \.offset) { _, city in
                    HStack(spacing: 4) {
                        Text(city.name).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(time(city) + shift(city)).monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                }
                if snapshot.cities.isEmpty { Text("Add cities in Meridian").font(.system(size: 13)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
