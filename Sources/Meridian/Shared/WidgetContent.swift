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

    /// On a widget, night tiles are lifted just above the widget's own background so every hour
    /// reads as a tile (the darkest hours otherwise vanish into it).
    static func style(at hour: Double, lifted: Bool) -> (fill: Color, text: Color) {
        guard lifted else { return style(at: hour) }
        var rgb = rgbAt(hour)
        let floor = components(0x2E2A26)
        rgb = (max(rgb.0, floor.0), max(rgb.1, floor.1), max(rgb.2, floor.2))
        let luminance = 0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), luminance > 0.45 ? WidgetTone.bg : WidgetTone.secondary)
    }

    private static func rgbAt(_ hour: Double) -> (Double, Double, Double) {
        let h = hour.truncatingRemainder(dividingBy: 24)
        var rgb = components(stops[0].1)
        for i in 0..<(stops.count - 1) where h >= stops[i].0 && h <= stops[i + 1].0 {
            let a = components(stops[i].1), b = components(stops[i + 1].1)
            let span = stops[i + 1].0 - stops[i].0
            let t = span == 0 ? 0 : (h - stops[i].0) / span
            rgb = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            break
        }
        return rgb
    }

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

/// The widget's background: warm near-black with the crimson rule, which steps aside in tinted and
/// clear modes (as Two Degrees does). The system's content margins keep the face clear of it.
struct MeridianWidgetBackground: View {
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        ZStack(alignment: .top) {
            WidgetTone.bg
            if renderingMode == .fullColor { WidgetTone.crimson.frame(height: 3) }
        }
    }
}

/// In-app renders of a widget (screenshots, the Mac self-test), which have no system margins or
/// container background, so this adds both.
struct WidgetFacePreview: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily
    let size: CGSize

    var body: some View {
        WidgetClockView(snapshot: snapshot, date: date, family: family, isPreview: true)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { MeridianWidgetBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

/// A widget time: the digits, then AM/PM smaller and raised (Two Degrees' reading style).
enum WidgetClockText {
    static func text(_ digits: String, suffix: String?, size: CGFloat) -> Text {
        let main = Text(digits)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .tracking(-size * 0.03)
        guard let suffix else { return main }
        return main + Text("\u{2009}" + suffix)
            .font(.system(size: size * 0.42, weight: .medium))
            .baselineOffset(size * 0.36)
    }
}

/// The widget face for each size: small shows one city, medium two side by side (each with its
/// hour before and after), large five with the hour before, now and the hour after.
struct WidgetClockView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily
    /// Set by in-app renders (WidgetFacePreview), which always draw in full colour.
    var isPreview = false

    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.showsWidgetContainerBackground) var showsBackground

    /// Accented, vibrant (Lock Screen, tinted Home Screen) or clear (StandBy): no opaque blocks,
    /// no brand colours; shapes and text in the system's primary colour.
    private var tinted: Bool {
        renderingMode != .fullColor || (!showsBackground && !isPreview)
    }

    /// The hairline between the two medium cells and under the large header.
    private static let ruleTone = Color(red: 58.0 / 255, green: 53.0 / 255, blue: 48.0 / 255)   // #3A3530
    private var rule: Color { tinted ? Color.primary.opacity(0.3) : Self.ruleTone }
    /// "Now" labels and outlines: cream in full colour.
    private var nowTone: Color { tinted ? Color.primary : WidgetTone.cream }

    var body: some View {
        Group {
            if cities.isEmpty {
                VStack(spacing: 4) {
                    Text("No cities yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add cities in Meridian")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTone.muted)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch family {
                case .systemLarge:
                    strip
                case .systemMedium:
                    HStack(alignment: .top, spacing: 14) {
                        cityCell(cities[0], timeSize: 34).frame(maxWidth: .infinity, alignment: .leading)
                        if cities.count > 1 {
                            Rectangle().fill(rule).frame(width: 0.5)
                            cityCell(cities[1], timeSize: 34).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                default:
                    cityCell(cities[0], timeSize: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(WidgetTone.primary)
    }

    private var cityLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        default: return 5   // large: five rows fill it (four left its bottom empty)
        }
    }

    private var cities: [WidgetSnapshot.City] { Array(snapshot.cities.prefix(cityLimit)) }

    // MARK: Small and medium: one city, big, with its next hours

    private func cityCell(_ city: WidgetSnapshot.City, timeSize: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        return VStack(alignment: .leading, spacing: 0) {
            Text(city.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            WidgetClockText.text(clock, suffix: suffix, size: timeSize)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption(zone))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetTone.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            // The hour before, now (outlined) and the hour after, each labelled.
            HStack(spacing: 4) {
                ForEach(-1...1, id: \.self) { k in
                    VStack(spacing: 3) {
                        Text(k == 0 ? "Now" : (k > 0 ? "+1 hr" : "−1 hr"))
                            .font(.system(size: 10, weight: k == 0 ? .semibold : .medium))
                            .foregroundStyle(k == 0 ? nowTone : WidgetTone.muted)
                            .lineLimit(1)
                        tile(anchor.addingTimeInterval(Double(k) * 3600), zone: zone)
                            .frame(height: 22)
                            .overlay {
                                if k == 0 {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(nowTone, lineWidth: 1.5)
                                        .widgetAccentable()
                                }
                            }
                    }
                }
            }
        }
    }

    /// "Tomorrow", "Yesterday", "+2 d" or nil on the same day as here (as Apple's Clock does).
    private func dayWord(_ zone: TimeZone, short: Bool) -> String? {
        let shift = Self.dayShift(date, zone: zone)
        if shift == 0 { return nil }
        if !short && shift == 1 { return "Tomorrow" }
        if !short && shift == -1 { return "Yesterday" }
        return shift > 0 ? "+\(shift) d" : "−\(-shift) d"
    }

    /// Under the time: "Tomorrow · +8 hr" on another day, otherwise "+8 hr" or "Your time".
    private func caption(_ zone: TimeZone, short: Bool = false) -> String {
        if let day = dayWord(zone, short: short) { return "\(day) · \(relative(zone))" }
        return relative(zone)
    }

    /// "−5 hr", "+5:30 hr" or "Your time".
    private func relative(_ zone: TimeZone) -> String {
        let diff = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return zone.identifier == TimeZone.current.identifier ? "Your time" : "Same time" }
        let sign = diff > 0 ? "+" : "−"
        let hours = abs(diff) / 3600
        let minutes = (abs(diff) % 3600) / 60
        return "\(sign)\(hours)\(minutes == 0 ? "" : ":\(String(format: "%02d", minutes))") hr"
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
                    Color.clear.frame(width: labelWidth, height: 1)
                    ForEach(-half...half, id: \.self) { k in
                        Text(k == 0 ? "Now" : (k > 0 ? "+\(k) hr" : "−\(-k) hr"))
                            .font(.system(size: 10, weight: k == 0 ? .semibold : .medium))
                            .foregroundStyle(k == 0 ? nowTone : WidgetTone.muted)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: pitch)
                    }
                }
                .frame(height: headerHeight, alignment: .top)
                // The rule under the header, inside its height so the row geometry is unchanged.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(rule).frame(height: 0.5)
                }

                ForEach(Array(cities.enumerated()), id: \.offset) { _, city in
                    let zone = TimeZone(identifier: city.timeZoneID) ?? .current
                    let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(city.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WidgetTone.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                WidgetClockText.text(clock, suffix: suffix, size: 22)
                                    .widgetAccentable()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .layoutPriority(1)
                                Text(caption(zone, short: true))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WidgetTone.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tinted ? Color.primary.opacity(0.6) : WidgetTone.cream, lineWidth: 1.5)
                    .widgetAccentable()
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
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60, lifted: true)
        let newDay = !calendar.isDate(moment, inSameDayAs: moment.addingTimeInterval(-3600))
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let label: Text = {
            var text = snapshot.use24h ? Text(String(format: "%02d", hour)) : Text("\(hour % 12 == 0 ? 12 : hour % 12)")
            // Half-hour and 45-minute zones: "05:30" reads "05" + small ":30".
            if minute != 0 { text = text + Text(":\(String(format: "%02d", minute))").font(.system(size: 9, weight: .medium)) }
            if !snapshot.use24h { text = text + Text("\u{2009}" + (hour < 12 ? "AM" : "PM")).font(.system(size: 8, weight: .medium)) }
            return text
        }()
        return label
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(tinted ? Color.primary : style.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // Tinted modes: an outline, not an opaque block.
                if tinted {
                    shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                } else {
                    shape.fill(style.fill)
                }
            }
            .overlay(alignment: .leading) {
                // A new day starts at midnight.
                if newDay {
                    Capsule().fill(tinted ? Color.primary : WidgetTone.crimson)
                        .frame(width: 2).padding(.vertical, 6).offset(x: -3)
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

    /// "14:05" or "2:05 PM" (AM and PM always spelled out, Apple's style).
    static func time(_ date: Date, zone: TimeZone, use24h: Bool, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = use24h ? "HH:mm" : "h:mm\u{2009}a"   // thin space before AM/PM
        return formatter.string(from: date)
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
        return d == 0 ? "" : (d > 0 ? " +\(d) d" : " −\(-d) d")
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
                VStack(spacing: -1) {
                    Text(tag(city))
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                    Text(time(city))
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .widgetAccentable()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(4)
            } else {
                Image(systemName: "globe")
            }
        default:
            // Rectangular: three cities, one per line.
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(snapshot.cities.prefix(3).enumerated()), id: \.offset) { _, city in
                    let (clock, suffix) = WidgetClockView.clock(date, zone: zone(city), use24h: snapshot.use24h)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(city.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 2)
                        // Another day stays visible ("+1 d"), as before.
                        (WidgetClockText.text(clock, suffix: suffix, size: 15)
                            + Text(shift(city)).font(.system(size: 11, weight: .medium)))
                            .lineLimit(1)
                            .layoutPriority(1)
                            .widgetAccentable()
                    }
                }
                if snapshot.cities.isEmpty { Text("Add cities in Meridian").font(.system(size: 13)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
