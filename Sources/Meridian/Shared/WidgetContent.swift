import SwiftUI
import WidgetKit
#if os(iOS)
import ImageIO
#endif

// Shared by the Mac app, the iPhone app (ios/) and both widget extensions (Widget/MeridianWidget.swift),
// so this file stands alone: no Palette, Metrics or ZoneStore. The app writes a WidgetSnapshot whenever cities
// or clock settings change; the widget reads it and draws the same day/night tiles.

/// What the widget needs from the app: cities in order and the clock settings.
struct WidgetSnapshot: Codable, Equatable {
    struct City: Codable, Equatable {
        var name: String
        var timeZoneID: String
        /// From the iPhone app, for the widget's sky (sunrise and sunset) and working status;
        /// nil uses the time zone's (and older files, the Mac and widget-chosen cities have none).
        var countryCode: String? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var workDays: [Int]? = nil
        var workStart: Int? = nil
        var workEnd: Int? = nil

        /// "London|Europe/London", as the widget's city picker and the photo index name it.
        var id: String { WidgetSkylines.id(name: name, timeZoneID: timeZoneID) }
    }

    var cities: [City]
    var use24h: Bool
    /// The iPhone app's working-hours settings, for each city's status (nil: on, 9 to 18, holidays counted).
    var showStatus: Bool? = nil
    var workStart: Int? = nil
    var workEnd: Int? = nil
    var countHolidays: Bool? = nil

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

/// The widget's container background: on iPhone the small widget is its city's skyline photo,
/// filling it (as the app's cards are); otherwise, and on the Mac, MeridianWidgetBackground.
struct WidgetContainerBackground: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily
    var isPreview = false

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        #if os(iOS)
        if family == .systemSmall, renderingMode == .fullColor, let city = snapshot.cities.first {
            WidgetCityBackdrop(city: city, date: date, image: WidgetSkylines.image(for: city))
        } else {
            MeridianWidgetBackground()
        }
        #else
        MeridianWidgetBackground()
        #endif
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
            .background { WidgetContainerBackground(snapshot: snapshot, date: date, family: family, isPreview: true) }
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
        #if os(iOS)
        if !tinted && !cities.isEmpty {
            photoFace
        } else {
            classicFace
        }
        #else
        classicFace
        #endif
    }

    #if os(iOS)
    /// iPhone, in full colour: each city its skyline photo, as the app's cards (small: one city
    /// filling the widget, its photo the container background).
    @ViewBuilder private var photoFace: some View {
        if family == .systemSmall {
            WidgetSmallPhotoFace(snapshot: snapshot, city: cities[0], date: date)
        } else {
            WidgetPhotoRows(snapshot: snapshot, cities: cities, date: date)
        }
    }
    #endif

    /// The Mac's face, and the iPhone's in tinted and clear modes.
    private var classicFace: some View {
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

// MARK: - Skyline photos (iPhone)

/// The widgets' skyline photos. The iPhone app writes a small copy of each city's photo (~600×300
/// JPEG) into the App Group container (Skylines/<key>.jpg) with Skylines/index.json naming each
/// city's file; the widget reads them downsampled and never uses the network.
enum WidgetSkylines {
    /// "London|Europe/London".
    static func id(name: String, timeZoneID: String) -> String { "\(name)|\(timeZoneID)" }

    #if os(iOS)
    /// A city's photo in the index: its file in Skylines, and where it came from ("b:london" built
    /// in, "d:<slug>" downloaded), so the app rewrites it only when that changes.
    struct Entry: Codable, Equatable {
        var file: String
        var source: String
    }

    static let maxPixels = 600

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appendingPathComponent("Skylines", isDirectory: true)
    }

    static var indexURL: URL? { directory?.appendingPathComponent("index.json") }

    static func readIndex() -> [String: Entry] {
        guard let url = indexURL, let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return index
    }

    private static let lock = NSLock()
    /// Decoded photos by file and modification date (a rewritten file is read again).
    private static var images: [String: CGImage] = [:]
    private static var index: (stamp: Date?, entries: [String: Entry])?

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Set by the app in screenshot mode so its widget previews show the cities' photos without
    /// anything written to the shared folder.
    static var inAppImage: ((WidgetSnapshot.City) -> CGImage?)?

    /// The city's photo, downsampled to at most 600 px, or nil (the widget then draws its sky).
    static func image(for city: WidgetSnapshot.City) -> CGImage? {
        if let provide = inAppImage { return provide(city) }
        guard let dir = directory, let indexURL = indexURL else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let stamp = modified(indexURL)
        let entries: [String: Entry]
        if let cached = index, cached.stamp == stamp {
            entries = cached.entries
        } else {
            entries = readIndex()
            index = (stamp, entries)
        }
        guard let entry = entries[city.id] else { return nil }
        let url = dir.appendingPathComponent(entry.file)
        guard let fileStamp = modified(url) else { return nil }
        let key = "\(entry.file)|\(fileStamp.timeIntervalSinceReferenceDate)"
        if let hit = images[key] { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // A widget has little memory: keep only a few (a large widget shows five).
        if images.count >= 8 { images.removeAll() }
        images[key] = image
        return image
    }

    /// Whether the card is bright behind the time: the area `region` covers (unit square, top-left
    /// origin) of a card of `aspect` (width / height), shaded for the phase and darkened by the
    /// scrim, as the app judges it.
    static func isBright(_ image: CGImage?, phase: WidgetSky.Phase, aspect: CGFloat, region: CGRect) -> Bool {
        let luminance = image.flatMap { photoLuminance($0, phase: phase, aspect: aspect, region: region) }
            ?? skyLuminance(phase, region: region)
        return luminance > 0.40
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static var brightness: [String: Double] = [:]

    private static func photoLuminance(_ image: CGImage, phase: WidgetSky.Phase, aspect: CGFloat, region: CGRect) -> Double? {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, aspect > 0 else { return nil }
        let cacheKey = "\(ObjectIdentifier(image).hashValue)|\(phase)|\(Int(aspect * 4))|\(region.minX),\(region.minY),\(region.width),\(region.height)"
        lock.lock()
        let hit = brightness[cacheKey]
        lock.unlock()
        if let hit { return hit }
        // The part the card shows (filling it, centred), then the region of that.
        var visible = CGRect(x: 0, y: 0, width: iw, height: ih)
        if iw / ih > aspect {
            let vw = ih * aspect
            visible = CGRect(x: (iw - vw) / 2, y: 0, width: vw, height: ih)
        } else {
            let vh = iw / aspect
            visible = CGRect(x: 0, y: (ih - vh) / 2, width: iw, height: vh)
        }
        let crop = CGRect(x: visible.minX + visible.width * region.minX, y: visible.minY + visible.height * region.minY,
                          width: visible.width * region.width, height: visible.height * region.height).integral
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard !crop.isNull, !crop.isEmpty, let part = image.cropping(to: crop) else { return nil }
        let w = 24, h = 12
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let saturation = WidgetSky.saturation(phase)
        let tint = WidgetSky.shadeComponents(phase)
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
                let grey = 0.2126 * r + 0.7152 * g + 0.0722 * b
                r = min(max(grey + (r - grey) * saturation, 0), 1)
                g = min(max(grey + (g - grey) * saturation, 0), 1)
                b = min(max(grey + (b - grey) * saturation, 0), 1)
                let k = WidgetScrim.remaining(u: u, v: v)
                total += luminance(r * tint.0 * k, g * tint.1 * k, b * tint.2 * k)
            }
        }
        let result = total / Double(w * h)
        lock.lock()
        if brightness.count > 60 { brightness.removeAll() }
        brightness[cacheKey] = result
        lock.unlock()
        return result
    }

    /// The fallback sky's gradient over the region, darkened by the scrim.
    private static func skyLuminance(_ phase: WidgetSky.Phase, region: CGRect) -> Double {
        let (top, bottom) = WidgetSky.skyHex(phase)
        let a = DayColor.components(top), b = DayColor.components(bottom)
        var total = 0.0
        let rows = 8, cols = 8
        for row in 0..<rows {
            let v = Double(region.minY) + Double(region.height) * (Double(row) + 0.5) / Double(rows)
            for col in 0..<cols {
                let u = Double(region.minX) + Double(region.width) * (Double(col) + 0.5) / Double(cols)
                let k = WidgetScrim.remaining(u: u, v: v)
                total += luminance((a.0 + (b.0 - a.0) * v) * k, (a.1 + (b.1 - a.1) * v) * k, (a.2 + (b.2 - a.2) * v) * k)
            }
        }
        return total / Double(rows * cols)
    }
    #endif
}

#if os(iOS)
/// The time of day at a city, as the app's cards shade it: within an hour of sunrise or sunset
/// (and the hour after) is twilight.
enum WidgetSky {
    enum Phase: Hashable { case night, twilight, day }

    static func phase(_ city: WidgetSnapshot.City, at date: Date) -> Phase {
        let now = raw(city, at: date)
        let hourAgo = raw(city, at: date.addingTimeInterval(-3600))
        return (now != .twilight && hourAgo != now) ? .twilight : now
    }

    private static func raw(_ city: WidgetSnapshot.City, at date: Date) -> Phase {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let sun: Sun.Phase?
        if let lat = city.latitude, let lon = city.longitude {
            sun = Sun.phase(lat: lat, lon: lon, zone: zone, at: date)
        } else {
            sun = Sun.phase(zoneID: city.timeZoneID, at: date)
        }
        switch sun {
        case .day(let sets)?: return sets.timeIntervalSince(date) < 3600 ? .twilight : .day
        case .night(let rises)?: return rises.timeIntervalSince(date) < 3600 ? .twilight : .night
        case .allDay?: return .day
        case .allNight?: return .night
        case nil:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            return (7..<19).contains(cal.component(.hour, from: date)) ? .day : .night
        }
    }

    /// The photo's tint: darker and cooler at night, warmer in twilight, as it is by day.
    static func shadeComponents(_ phase: Phase) -> (Double, Double, Double) {
        switch phase {
        case .night: return (0.42, 0.45, 0.55)
        case .twilight: return (0.95, 0.84, 0.72)
        case .day: return (1, 1, 1)
        }
    }

    static func shade(_ phase: Phase) -> Color {
        let c = shadeComponents(phase)
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    static func saturation(_ phase: Phase) -> Double {
        switch phase {
        case .night: return 0.75
        case .twilight: return 1.1
        case .day: return 1
        }
    }

    /// The sky drawn when a city has no photo, top to bottom.
    static func skyHex(_ phase: Phase) -> (UInt32, UInt32) {
        switch phase {
        case .day: return (0x4A80BD, 0xA9CBEA)
        case .twilight: return (0x2B3A6B, 0xF08A5D)
        case .night: return (0x0B1022, 0x1A2340)
        }
    }

    static func sky(_ phase: Phase) -> [Color] {
        let (top, bottom) = skyHex(phase)
        return [top, bottom].map { hex in
            let c = DayColor.components(hex)
            return Color(red: c.0, green: c.1, blue: c.2)
        }
    }
}

/// Where a city is in its working week, as the app's status pill says it (Working, Off hours,
/// Weekend, Day off, or the holiday's name), from the settings the app hands the widget.
struct WidgetWorkStatus {
    enum Kind { case working, offHours, weekend, dayOff, holiday }
    let kind: Kind
    let title: String

    var color: Color {
        let hex: UInt32
        switch kind {
        case .working: hex = 0x9FE3A6
        case .offHours: hex = 0xB9B2A8
        case .weekend, .dayOff: hex = 0xF4C47A
        case .holiday: hex = 0xF29BB5
        }
        let c = DayColor.components(hex)
        return Color(red: c.0, green: c.1, blue: c.2)
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

    static func makePlace(_ city: WidgetSnapshot.City) -> Place {
        var place = Place(name: city.name, timeZoneID: city.timeZoneID)
        place.countryCode = city.countryCode
        place.latitude = city.latitude
        place.longitude = city.longitude
        place.workDays = city.workDays.map { Set($0) }
        place.workStart = city.workStart
        place.workEnd = city.workEnd
        return place
    }

    /// Follows the app's Count Holidays setting (the widget keeps its own copy of it).
    private static func applySettings(_ snapshot: WidgetSnapshot) {
        if let counted = snapshot.countHolidays, Holidays.counted != counted { Holidays.counted = counted }
    }

    /// Nil when the app's Highlight Working Hours is off.
    static func of(_ city: WidgetSnapshot.City, snapshot: WidgetSnapshot, at date: Date) -> WidgetWorkStatus? {
        guard snapshot.showStatus ?? true else { return nil }
        applySettings(snapshot)
        let place = makePlace(city)
        let start = snapshot.workStart ?? 9, end = snapshot.workEnd ?? 18
        guard let off = WorkWeek.offLabel(place, at: date, start: start, end: end) else {
            return WidgetWorkStatus(kind: .working, title: "Working")
        }
        let kind: Kind
        switch off {
        case "Off hours": kind = .offHours
        case "Weekend": kind = .weekend
        case "Day off": kind = .dayOff
        default: kind = .holiday
        }
        return WidgetWorkStatus(kind: kind, title: off)
    }

    /// An hour tile is dimmed outside working hours (when the app highlights them).
    static func dims(_ city: WidgetSnapshot.City, snapshot: WidgetSnapshot, hourStart: Date) -> Bool {
        guard snapshot.showStatus ?? true else { return false }
        applySettings(snapshot)
        return !WorkWeek.isWorking(makePlace(city), at: hourStart.addingTimeInterval(1800),
                                   start: snapshot.workStart ?? 9, end: snapshot.workEnd ?? 18)
    }
}

/// The card's scrim, as the app's: black at 55% along the bottom, gone by 55% of the way up, and
/// a lighter one from the left (35%, gone by 60% across).
struct WidgetScrim: View {
    static let bottomOpacity = 0.55
    static let bottomReach = 0.55
    static let leftOpacity = 0.35
    static let leftReach = 0.6

    static func remaining(u: Double, v: Double) -> Double {
        let up = bottomOpacity * max(0, 1 - (1 - v) / bottomReach)
        let across = leftOpacity * max(0, 1 - u / leftReach)
        return (1 - up) * (1 - across)
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: [
                Gradient.Stop(color: Color.black.opacity(Self.bottomOpacity), location: 0),
                Gradient.Stop(color: Color.black.opacity(0), location: Self.bottomReach),
            ], startPoint: .bottom, endPoint: .top)
            LinearGradient(stops: [
                Gradient.Stop(color: Color.black.opacity(Self.leftOpacity), location: 0),
                Gradient.Stop(color: Color.black.opacity(0), location: Self.leftReach),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// A city's photo filling the space, shaded for the time of day there, or its sky when there's no
/// photo, with the scrim over it.
struct WidgetCityBackdrop: View {
    let city: WidgetSnapshot.City
    let date: Date
    let image: CGImage?

    var body: some View {
        let phase = WidgetSky.phase(city, at: date)
        ZStack {
            if let image {
                Color.clear
                    .overlay {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .saturation(WidgetSky.saturation(phase))
                            .colorMultiply(WidgetSky.shade(phase))
                    }
                    .clipped()
            } else {
                LinearGradient(colors: WidgetSky.sky(phase), startPoint: .top, endPoint: .bottom)
            }
            WidgetScrim()
        }
    }
}

/// The time on a photo, as the app's: semibold digits, AM/PM small after; white outlined in dark
/// on a dark photo, near-black outlined in white on a bright one.
struct WidgetBannerClock: View {
    let date: Date
    let zone: TimeZone
    let use24h: Bool
    let size: CGFloat
    var bright = false

    private static let directions: [CGSize] = {
        let d = CGFloat(0.5.squareRoot())
        return [CGSize(width: -1, height: 0), CGSize(width: 1, height: 0),
                CGSize(width: 0, height: -1), CGSize(width: 0, height: 1),
                CGSize(width: -d, height: -d), CGSize(width: d, height: -d),
                CGSize(width: -d, height: d), CGSize(width: d, height: d)]
    }()

    var body: some View {
        let parts = WidgetClockView.clock(date, zone: zone, use24h: use24h)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            outlined(Text(parts.0).font(.system(size: size, weight: .semibold)).monospacedDigit().tracking(-0.02 * size),
                     width: size / 24)
            if let suffix = parts.1 {
                outlined(Text("\u{2009}" + suffix).font(.system(size: size * 0.45, weight: .medium)),
                         width: size * 0.45 / 24)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.4 : 0.35), radius: 3, x: 0, y: 0)
    }

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
            t.foregroundStyle(bright ? Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x10 / 255.0) : Color.white)
        }
    }
}

/// The app's status pill, small: an icon and the status in its colour on a dark backing.
struct WidgetStatusPill: View {
    let status: WidgetWorkStatus
    var size: CGFloat = 9.5

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.system(size: size * 0.78, weight: .semibold))
            Text(status.title)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(status.color.opacity(0.35), lineWidth: 1))
    }
}

/// The city name on a photo, with a soft shadow.
private func widgetCityName(_ name: String, size: CGFloat) -> some View {
    Text(name)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.8)
        .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
}

/// Medium and large: each city a row filled with its skyline photo (rounded, small gaps), the time,
/// name and status bottom-left and the hour before, the hour now and the hour after bottom-right;
/// one Now capsule runs down the middle tiles of every row, as in the app.
struct WidgetPhotoRows: View {
    let snapshot: WidgetSnapshot
    let cities: [WidgetSnapshot.City]
    let date: Date

    static let gap: CGFloat = 5
    static let radius: CGFloat = 12
    static let sidePadding: CGFloat = 9
    static let bottomPadding: CGFloat = 7
    static let tileGap: CGFloat = 4
    /// The capsule past the middle tile on each side, and above the first row's and below the last's.
    static let outset: CGFloat = 4
    static let overhang: CGFloat = 10
    static let stroke: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let n = max(cities.count, 1)
            let rowHeight = max(30, ((geo.size.height - Self.gap * CGFloat(n - 1)) / CGFloat(n)).rounded(.down))
            let tileHeight = min(44, max(22, rowHeight - 24))
            let tileWidth = min(40, ((geo.size.width * 0.42 - 2 * Self.tileGap) / 3).rounded(.down))
            VStack(spacing: Self.gap) {
                ForEach(Array(cities.enumerated()), id: \.offset) { _, city in
                    row(city, width: geo.size.width, height: rowHeight, tileWidth: tileWidth, tileHeight: tileHeight)
                }
            }
            .frame(width: geo.size.width, alignment: .top)
            .overlay(alignment: .topLeading) {
                capsule(width: geo.size.width, rows: cities.count, rowHeight: rowHeight,
                        tileWidth: tileWidth, tileHeight: tileHeight)
            }
        }
    }

    /// One capsule through the middle tile of every row.
    private func capsule(width: CGFloat, rows: Int, rowHeight: CGFloat, tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let middleLeft = width - Self.sidePadding - 2 * tileWidth - Self.tileGap
        let top = rowHeight - Self.bottomPadding - tileHeight - Self.overhang
        let bottom = CGFloat(max(rows, 1) - 1) * (rowHeight + Self.gap) + rowHeight - Self.bottomPadding + Self.overhang
        let shape = Capsule(style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.white.opacity(0.62), lineWidth: Self.stroke))
            .shadow(color: Color.white.opacity(0.18), radius: 6)
            .frame(width: tileWidth + 2 * Self.outset, height: max(1, bottom - top))
            .offset(x: middleLeft - Self.outset, y: top)
    }

    private func row(_ city: WidgetSnapshot.City, width: CGFloat, height: CGFloat,
                     tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let image = WidgetSkylines.image(for: city)
        let phase = WidgetSky.phase(city, at: date)
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        let clockSize = min(34, max(17, (height * 0.28).rounded()))
        // About where the time sits: bottom left, above the name (and status).
        let clockBottom = height - Self.bottomPadding - (status == nil ? 16 : 30)
        let region = CGRect(x: Self.sidePadding / max(width, 1), y: max(0, clockBottom - clockSize * 1.2) / height,
                            width: min(0.5, clockSize * 3 / max(width, 1)), height: min(1, clockSize * 1.2 / height))
        let bright = WidgetSkylines.isBright(image, phase: phase, aspect: width / max(height, 1), region: region)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        return ZStack(alignment: .bottomLeading) {
            WidgetCityBackdrop(city: city, date: date, image: image)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: clockSize, bright: bright)
                        .widgetAccentable()
                        .layoutPriority(1)
                    ViewThatFits(in: .vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            widgetCityName(city.name, size: 12)
                            if let status { WidgetStatusPill(status: status) }
                        }
                        widgetCityName(city.name, size: 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                HStack(spacing: Self.tileGap) {
                    ForEach(-1...1, id: \.self) { k in
                        WidgetPhotoTile(snapshot: snapshot, city: city, zone: zone,
                                        start: anchor.addingTimeInterval(Double(k) * 3600), center: k == 0)
                            .frame(width: tileWidth, height: tileHeight)
                    }
                }
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
            .padding(.horizontal, Self.sidePadding)
            .padding(.top, 2)
            .padding(.bottom, Self.bottomPadding)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }
}

/// An hour tile on a photo, as the app's: the day's colour there at that hour (dimmed outside
/// working hours), the hour with AM/PM under it, and a crimson mark where a new day starts.
struct WidgetPhotoTile: View {
    let snapshot: WidgetSnapshot
    let city: WidgetSnapshot.City
    let zone: TimeZone
    let start: Date
    let center: Bool

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        let newDay = !calendar.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
        let dim = WidgetWorkStatus.dims(city, snapshot: snapshot, hourStart: start)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(spacing: 0) {
            label(hour: hour, minute: minute)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !snapshot.use24h {
                Text(hour < 12 ? "AM" : "PM")
                    .font(.system(size: 7.5, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(style.text)
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(style.fill.opacity(dim ? 0.72 : 1)))
        .overlay(alignment: .leading) {
            if newDay {
                Capsule().fill(WidgetTone.crimson)
                    .frame(width: 2).padding(.vertical, 6).offset(x: -(WidgetPhotoRows.tileGap / 2 + 1))
            }
        }
    }

    /// "9" or "09", with ":30" small in half-hour zones.
    private func label(hour: Int, minute: Int) -> Text {
        var text = Text(snapshot.use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)")
            .font(.system(size: 13, weight: center ? .semibold : .medium))
        if minute != 0 {
            text = text + Text(":" + String(format: "%02d", minute)).font(.system(size: 8.5, weight: .medium))
        }
        return text
    }
}

/// Small: one city, its photo filling the widget (the container background), the time large at
/// the bottom left with its name and status.
struct WidgetSmallPhotoFace: View {
    let snapshot: WidgetSnapshot
    let city: WidgetSnapshot.City
    let date: Date

    var body: some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let phase = WidgetSky.phase(city, at: date)
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        let bright = WidgetSkylines.isBright(WidgetSkylines.image(for: city), phase: phase, aspect: 1,
                                             region: CGRect(x: 0.08, y: status == nil ? 0.5 : 0.4, width: 0.6, height: 0.25))
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: 34, bright: bright)
                .widgetAccentable()
            widgetCityName(city.name, size: 14)
            if let status {
                WidgetStatusPill(status: status, size: 10)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
#endif
