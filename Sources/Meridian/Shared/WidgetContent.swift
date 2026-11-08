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

/// Sky through the day. iPhone: Two Degrees' sky (navy night, blue dawn and dusk, sky blue by day).
/// Mac: bradcowdrey.com tones (warm black at night, warm greys at twilight, cream in daylight).
enum DayColor {
    #if os(iOS)
    private static let stops: [(Double, UInt32)] = [
        (0, 0x0A0E1C),
        (5, 0x141E3C),
        (6.5, 0x24384F),
        (8, 0x1C3A5E),
        // The bright daytime steps are Two Degrees' sky blues held a little darker (#3D74B0 and
        // #4F78A3 were 4.9 and 4.6:1 under white), so the hour and its AM/PM, the product's
        // smallest text, keep at least 5.9:1 (#34609A 6.4:1, #3A6699 5.9:1).
        (9.5, 0x34609A),
        (12, 0x3A6699),
        (15, 0x3A6699),
        (17.5, 0x34609A),
        (19, 0x1C3A5E),
        (20.5, 0x24384F),
        (22, 0x141E3C),
        (24, 0x0A0E1C),
    ]
    /// The lifted widget tiles' floor (Two Degrees' partly-cloudy bottom).
    private static let liftFloor: UInt32 = 0x24384F
    #else
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
    private static let liftFloor: UInt32 = 0x2E2A26
    #endif

    /// On a widget, night tiles are lifted just above the widget's own background so every hour
    /// reads as a tile (the darkest hours otherwise vanish into it).
    static func style(at hour: Double, lifted: Bool) -> (fill: Color, text: Color) {
        guard lifted else { return style(at: hour) }
        var rgb = rgbAt(hour)
        let floor = components(liftFloor)
        rgb = (max(rgb.0, floor.0), max(rgb.1, floor.1), max(rgb.2, floor.2))
        #if os(iOS)
        // Every sky tone is dark enough for white text (the brightest, #3A6699, is 5.9:1).
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), Color.white)
        #else
        let luminance = 0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), luminance > 0.45 ? WidgetTone.bg : WidgetTone.secondary)
        #endif
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
        #if os(iOS)
        // Every sky tone is dark enough for white text (the brightest, #3A6699, is 5.9:1).
        let text = Color.white
        #else
        let luminance = 0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2
        let text = luminance > 0.55 ? WidgetTone.bg : WidgetTone.secondary
        #endif
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), text)
    }

    #if os(iOS)
    /// An hour outside working hours, as the app's tiles (HourTiles.offHours): the hour's sky at 55%
    /// of its luminance (never darker than the night tile, #0A0E1C), same hue, fully opaque, so the
    /// photo never shows through behind the numerals.
    static let offHoursFactor = 0.55
    static let offHoursFloor = 0.0048

    static func offHoursFill(at hour: Double) -> Color {
        let rgb = rgbAt(hour)
        func linear(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func encoded(_ l: Double) -> Double {
            min(max(l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055, 0), 1)
        }
        let lr = linear(rgb.0), lg = linear(rgb.1), lb = linear(rgb.2)
        let luminance = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
        guard luminance > 0 else { return Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
        let k = max(min(luminance, offHoursFloor), luminance * offHoursFactor) / luminance
        return Color(red: encoded(lr * k), green: encoded(lg * k), blue: encoded(lb * k))
    }
    #endif

    fileprivate static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// The brand palette, restated here so the widget extension doesn't need the app's Palette.
/// iPhone: Two Degrees' black, white at its opacities and its sunrise accent; Mac: bradcowdrey.com.
enum WidgetTone {
    #if os(iOS)
    static let bg = Color.black
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.78)
    static let muted = Color.white.opacity(0.6)
    static let faint = Color.white.opacity(0.4)
    static let cream = Color.white
    /// The new-day marker on the hour tiles (Two Degrees' TileAccent.sunrise).
    static let midnight = tone(0xF2C66D)
    /// No crimson on iPhone: kept as a name for shared code, it is the midnight accent.
    static let crimson = midnight
    /// The hairline between widget cells (Two Degrees' WidgetTone.divider).
    static let divider = Color.white.opacity(0.18)
    /// Two Degrees' neutral evening sky (its widget background with no weather).
    static let skyTop = tone(0x262A33)
    static let skyBottom = tone(0x111317)
    /// Dark ink for a time drawn on a bright photo (Two Degrees' darkest navy).
    static let ink = tone(0x0A0E1C)
    #else
    static let bg = tone(0x1A1816)
    static let primary = Color.white
    static let secondary = tone(0xE0D8D0)
    static let muted = tone(0xB0A898)
    static let faint = tone(0x807870)
    static let cream = tone(0xFFF1E5)
    static let crimson = tone(0x990F3D)
    static let midnight = crimson
    #endif

    private static func tone(_ hex: UInt32) -> Color {
        let c = DayColor.components(hex)
        return Color(red: c.0, green: c.1, blue: c.2)
    }
}

/// The widget's background. iPhone: Two Degrees' neutral evening sky. Mac: warm near-black with the
/// crimson rule, which steps aside in tinted and clear modes (as Two Degrees does). The system's
/// content margins keep the face clear of it.
struct MeridianWidgetBackground: View {
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        #if os(iOS)
        LinearGradient(colors: [WidgetTone.skyTop, WidgetTone.skyBottom], startPoint: .top, endPoint: .bottom)
        #else
        ZStack(alignment: .top) {
            WidgetTone.bg
            if renderingMode == .fullColor { WidgetTone.crimson.frame(height: 3) }
        }
        #endif
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
            let backdrop = WidgetSmallPhotoFace.backdrop(snapshot: snapshot, city: city, date: date)
            WidgetCityBackdrop(city: city, date: date, photo: backdrop.photo, boost: backdrop.backing.boost)
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
/// iPhone: AM/PM never below 11 pt, and raised only beside big digits (22 pt and up); beside
/// smaller ones (the Lock Screen's 15 pt) it sits on the baseline, where a tiny raised suffix
/// was unreadable.
enum WidgetClockText {
    static func text(_ digits: String, suffix: String?, size: CGFloat) -> Text {
        let main = Text(digits)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .tracking(-size * 0.03)
        guard let suffix else { return main }
        #if os(iOS)
        return main + Text("\u{2009}" + suffix)
            .font(.system(size: max(11, size * 0.42), weight: .semibold))
            .baselineOffset(size >= 22 ? size * 0.3 : 0)
        #else
        return main + Text("\u{2009}" + suffix)
            .font(.system(size: size * 0.42, weight: .medium))
            .baselineOffset(size * 0.36)
        #endif
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
    #if os(iOS)
    private static let ruleTone = WidgetTone.divider
    #else
    private static let ruleTone = Color(red: 58.0 / 255, green: 53.0 / 255, blue: 48.0 / 255)   // #3A3530
    #endif
    private var rule: Color { tinted ? Color.primary.opacity(0.3) : Self.ruleTone }

    /// The "Now", "+1 hr" labels and the tiles' text. iPhone: nothing under 11 pt (Apple's minimum);
    /// the Mac keeps its sizes.
    #if os(iOS)
    private static let labelSize: CGFloat = 11
    private static let tileSize: CGFloat = 13
    private static let tileSmallSize: CGFloat = 12
    private static let tileMinuteSize: CGFloat = 12
    private static let tileSmallWeight: Font.Weight = .semibold
    private static let tileMinScale: CGFloat = 0.85   // digits only; AM/PM never shrinks
    /// City names and zone captions never scale under 11 pt on iPhone.
    private static let nameMinScale: CGFloat = 0.85
    private static let largeNameMinScale: CGFloat = 0.85
    private static let captionMinScale: CGFloat = 1
    #else
    private static let labelSize: CGFloat = 10
    private static let tileSize: CGFloat = 12
    private static let tileSmallSize: CGFloat = 8
    private static let tileMinuteSize: CGFloat = 9
    private static let tileSmallWeight: Font.Weight = .medium
    private static let tileMinScale: CGFloat = 0.6
    private static let nameMinScale: CGFloat = 0.75
    private static let largeNameMinScale: CGFloat = 0.8
    private static let captionMinScale: CGFloat = 0.8
    #endif
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
                .minimumScaleFactor(Self.nameMinScale)
            WidgetClockText.text(clock, suffix: suffix, size: timeSize)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption(zone))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetTone.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(Self.captionMinScale)
            Spacer(minLength: 4)
            // The hour before, now (outlined) and the hour after, each labelled.
            HStack(spacing: 4) {
                ForEach(-1...1, id: \.self) { k in
                    VStack(spacing: 3) {
                        Text(k == 0 ? "Now" : (k > 0 ? "+1 hr" : "−1 hr"))
                            .font(.system(size: Self.labelSize, weight: k == 0 ? .semibold : .medium))
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
                            .font(.system(size: Self.labelSize, weight: k == 0 ? .semibold : .medium))
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
                                .minimumScaleFactor(Self.largeNameMinScale)
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
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(Self.captionMinScale)
                            }
                        }
                        .frame(width: labelWidth - 6, alignment: .leading)
                        .padding(.trailing, 6)

                        ForEach(-half...half, id: \.self) { k in
                            tile(anchor.addingTimeInterval(Double(k) * 3600), zone: zone,
                                 stacked: !snapshot.use24h && rowHeight >= 34)
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

    /// `stacked` (iPhone, tiles tall enough): AM/PM under the hour; the Mac ignores it.
    private func tile(_ moment: Date, zone: TimeZone, stacked: Bool = false) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: moment)
        let minute = calendar.component(.minute, from: moment)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60, lifted: true)
        let newDay = !calendar.isDate(moment, inSameDayAs: moment.addingTimeInterval(-3600))
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return tileLabel(hour: hour, minute: minute, stacked: stacked)
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
                    Capsule().fill(tinted ? Color.primary : WidgetTone.midnight)
                        .frame(width: 2).padding(.vertical, 6).offset(x: -3)
                }
            }
    }

    /// The tile's hour. iPhone: only the digits may shrink; AM/PM stays 12 pt, after the hour or,
    /// when `stacked`, under it, with the label clear of the tile's rounded corners.
    @ViewBuilder
    private func tileLabel(hour: Int, minute: Int, stacked: Bool) -> some View {
        #if os(iOS)
        let suffix: String? = snapshot.use24h ? nil : (hour < 12 ? "AM" : "PM")
        if stacked, let suffix {
            VStack(spacing: -1) {
                tileDigits(hour: hour, minute: minute)
                    .font(.system(size: Self.tileSize + 2, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(Self.tileScale(minute: minute, use24h: snapshot.use24h))
                Text(suffix)
                    .font(.system(size: Self.tileSmallSize, weight: Self.tileSmallWeight))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        } else if minute != 0, let suffix {
            // "12:30PM" on a 22 pt medium tile (tinted modes) can't stack: all of it shrinks together
            // rather than truncate.
            (tileDigits(hour: hour, minute: minute) + Text(suffix)
                .font(.system(size: Self.tileSmallSize, weight: Self.tileSmallWeight)))
                .font(.system(size: Self.tileSize, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                tileDigits(hour: hour, minute: minute)
                    .font(.system(size: Self.tileSize, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(Self.tileScale(minute: minute, use24h: snapshot.use24h))
                if let suffix {
                    Text("\u{2009}" + suffix)
                        .font(.system(size: Self.tileSmallSize, weight: Self.tileSmallWeight))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 3)
        }
        #else
        let label: Text = {
            var text = snapshot.use24h ? Text(String(format: "%02d", hour)) : Text("\(hour % 12 == 0 ? 12 : hour % 12)")
            // Half-hour and 45-minute zones: "05:30" reads "05" + small ":30".
            if minute != 0 {
                text = text + Text(":\(String(format: "%02d", minute))")
                    .font(.system(size: Self.tileMinuteSize, weight: .medium))
            }
            if !snapshot.use24h {
                // iPhone: no thin space before AM/PM when ":30" is shown, so "12:30 PM" fits small tiles.
                #if os(iOS)
                let gap = minute != 0 ? "" : "\u{2009}"
                #else
                let gap = "\u{2009}"
                #endif
                text = text + Text(gap + (hour < 12 ? "AM" : "PM"))
                    .font(.system(size: Self.tileSmallSize, weight: Self.tileSmallWeight))
            }
            return text
        }()
        label
            .font(.system(size: Self.tileSize, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(Self.tileScale(minute: minute, use24h: snapshot.use24h))
        #endif
    }

    #if os(iOS)
    /// "9" or "09", with ":30" smaller in half-hour zones.
    private func tileDigits(hour: Int, minute: Int) -> Text {
        var text = snapshot.use24h ? Text(String(format: "%02d", hour)) : Text("\(hour % 12 == 0 ? 12 : hour % 12)")
        if minute != 0 {
            text = text + Text(":\(String(format: "%02d", minute))")
                .font(.system(size: Self.tileMinuteSize, weight: .medium))
        }
        return text
    }
    #endif

    /// iPhone: half-hour digits ("12:30") may shrink further rather than truncate.
    private static func tileScale(minute: Int, use24h: Bool) -> CGFloat {
        #if os(iOS)
        return minute != 0 && !use24h ? 0.8 : tileMinScale
        #else
        return tileMinScale
        #endif
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
    /// "12:41 PM" (a regular space) or "14:05".
    private func inlineTime(_ city: WidgetSnapshot.City) -> String {
        let (clock, suffix) = WidgetClockView.clock(date, zone: zone(city), use24h: snapshot.use24h)
        return suffix.map { clock + " " + $0 } ?? clock
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
            // One line above the Lock Screen clock: "LON 14:05 · TYO 22:05", or "NY 12:41 PM · LON 5:41 PM"
            // with a full space before AM/PM (the thin space collapsed there to "12:41PM"), as everywhere else.
            // Falls back to the first city alone where both don't fit ("LON 5:41…" never shows).
            let list = snapshot.cities.filter { $0 != snapshot.cities.first || snapshot.cities.count == 1 }
            ViewThatFits {
                Text(list.prefix(2).map { "\(tag($0)) \(inlineTime($0))" }.joined(separator: " · "))
                Text(list.prefix(1).map { "\(tag($0)) \(inlineTime($0))" }.joined())
            }
        case .accessoryCircular:
            if let city = featured {
                // "SF", the digits (22 pt, never under 17.6) and AM/PM under them at 12 pt, so
                // "12:41 PM" no longer shrinks toward 12 pt to fit the circle.
                let (clock, suffix) = WidgetClockView.clock(date, zone: zone(city), use24h: snapshot.use24h)
                VStack(spacing: -2) {
                    Text(tag(city))
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.85)
                    Text(clock)
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .widgetAccentable()
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    if let suffix {
                        Text(suffix)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .widgetAccentable()
                    }
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
            // AM/PM kept 2 pt off the trailing edge (accessoryRectangular has no system inset there;
            // its ink ran to 1.3 pt from the bound).
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif

// MARK: - Skyline photos (iPhone)

/// The widgets' skyline photos. The iPhone app writes a small copy of each city's photo (~600×300
/// JPEG) into the App Group container (Skylines/<key>.jpg), and of its night photo when it has one
/// (Skylines/<key>-night.jpg), with Skylines/index.json naming each city's files; the widget reads
/// them downsampled and never uses the network.
enum WidgetSkylines {
    /// "London|Europe/London".
    static func id(name: String, timeZoneID: String) -> String { "\(name)|\(timeZoneID)" }

    #if os(iOS)
    /// A city's photo in the index: its file in Skylines, where it came from ("b:london" built
    /// in, "d:<slug>" downloaded), so the app rewrites it only when that changes, and its night
    /// photo's file when it has one (nil: the day photo is darkened at night, as before).
    struct Entry: Codable, Equatable {
        var file: String
        var source: String
        var night: String? = nil
    }

    /// A photo the widget shows: the image, whether it is a real night photo (shown as taken) and
    /// a key naming the file it came from (for the brightness cache).
    struct Photo {
        let image: CGImage
        let isNight: Bool
        let key: String
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
    /// anything written to the shared folder: the day photo, and the night one when there is one.
    static var inAppImage: ((WidgetSnapshot.City) -> CGImage?)?
    static var inAppNightImage: ((WidgetSnapshot.City) -> CGImage?)?

    /// The photo the city shows at `date`: its night photo once the sun has set there (until the
    /// hour before sunrise), otherwise, or when it has none, its day photo (which WidgetSky.look
    /// then tints for the time of day, as before). Nil: the widget draws its sky.
    static func photo(for city: WidgetSnapshot.City, at date: Date) -> Photo? {
        if WidgetSky.wantsNightPhoto(city, at: date), let night = image(for: city, night: true) {
            return night
        }
        return image(for: city, night: false)
    }

    /// The city's day or night photo, downsampled to at most 600 px, or nil.
    static func image(for city: WidgetSnapshot.City, night: Bool) -> Photo? {
        if let provide = night ? inAppNightImage : inAppImage {
            return provide(city).map { Photo(image: $0, isNight: night, key: "app|\(city.id)|\(night)") }
        }
        if inAppImage != nil { return nil }   // screenshot mode with no night photos given
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
        let file: String
        if night {
            // The entry's night file; else one indexed under "<id>|night"; else "<key>-night.jpg"
            // beside the day photo.
            if let named = entry.night ?? entries[city.id + "|night"]?.file {
                file = named
            } else {
                let stem = entry.file.hasSuffix(".jpg") ? String(entry.file.dropLast(4)) : entry.file
                file = stem + "-night.jpg"
            }
        } else {
            file = entry.file
        }
        let url = dir.appendingPathComponent(file)
        guard let fileStamp = modified(url) else { return nil }
        let key = "\(file)|\(fileStamp.timeIntervalSinceReferenceDate)"
        if let hit = images[key] { return Photo(image: hit, isNight: night, key: key) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // A widget has little memory: keep only a few (a large widget shows five, by day or night).
        if images.count >= 10 { images.removeAll() }
        images[key] = image
        return Photo(image: image, isNight: night, key: key)
    }

    /// What the scrim behind a card's text has to do: `boost`, a flat layer of extra black over the
    /// name, status and time (bottom-left, feathered 12 pt above and to the right, as Android's
    /// clear()) so the white text keeps at least 5:1 against the brightest twentieth (p95), sampled
    /// 6 pt past the glyphs, of the photo behind it, and `bright`, whether the area behind the time is still too bright for white and bright on
    /// average (the time then switches to dark ink, as the app's, and the boost covers the name only).
    struct Backing: Equatable {
        var boost = WidgetScrim.Boost()
        var bright = false
    }

    /// The feather around the boost, in points.
    static let boostFeather: CGFloat = 12

    /// `textRegion` and `timeRegion` are areas of a card of `size` in its unit square (top-left
    /// origin): where the name and status sit, and where the time does. The boost covers both.
    static func backing(_ photo: Photo?, phase: WidgetSky.Phase, size: CGSize,
                        textRegion: CGRect, timeRegion: CGRect) -> Backing {
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        let aspect = CGFloat(w / h)
        // The boost's shape: full over `region` and everything below and left of it, feathered
        // 12 pt above and to the right.
        func shaped(_ region: CGRect, amount: Double) -> WidgetScrim.Boost {
            let top = min(max(Double(region.minY), 0), 1)
            let right = min(max(Double(region.maxX), 0), 1)
            return WidgetScrim.Boost(amount: amount, top: top, right: right,
                                     featherV: min(Double(boostFeather) / h, top),
                                     featherH: min(Double(boostFeather) / w, 1 - right))
        }
        // Sampled (and boosted) 6 pt past the glyphs on every side, so the halo around the name and
        // the digits counts too (bright brick right beside "9:41" measured 4.35:1 when it didn't).
        func padded(_ region: CGRect) -> CGRect {
            let grown = region.insetBy(dx: CGFloat(-6 / w), dy: CGFloat(-6 / h))
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return grown.isNull || grown.isEmpty ? region : grown
        }
        let textRegion = padded(textRegion), timeRegion = padded(timeRegion)
        var boost = shaped(textRegion.union(timeRegion), amount: 0)
        guard let photo else {
            // No photo: the drawn sky alone (white text drops under 4.5:1 above 0.183).
            return Backing(boost: boost, bright: skyLuminance(phase, region: timeRegion) > 0.183)
        }
        // The smallest boost (of a few steps, up to 0.55) that brings the brightest twentieth behind
        // the name and status under 0.16 (white text 5:1; was the brightest tenth, which left the
        // worst pixels near 4.1:1); a dark night photo needs none. Sized for the name, not the time,
        // so a day photo still looks like day.
        for step in WidgetScrim.boostSteps {
            boost.amount = step
            let text = photoLuminance(photo, phase: phase, aspect: aspect, region: textRegion, boost: boost)?.p95 ?? 0
            if text <= 0.16 { break }
        }
        var time = photoLuminance(photo, phase: phase, aspect: aspect, region: timeRegion, boost: boost)
        // A partly lit area behind the time (a few bright facades on a dark backdrop) keeps white
        // ink: step the boost on (up to 0.65 for the time on a night photo, 0.55 on a day photo so it
        // still looks like day; the dark-ink fallback below takes a time that is still too bright)
        // until white reaches 5:1 on its brightest twentieth (was 4.5:1 on the brightest tenth: no
        // margin, and SF's "9:41" measured 4.35:1).
        if let t = time, t.p95 > 0.16, t.mean <= 0.40 {
            for step in (photo.isNight ? WidgetScrim.timeBoostSteps : WidgetScrim.boostSteps) where step > boost.amount {
                boost.amount = step
                time = photoLuminance(photo, phase: phase, aspect: aspect, region: timeRegion, boost: boost)
                if (time?.p95 ?? 0) <= 0.16 { break }
            }
        }
        // Dark ink only where white still can't reach 4.5:1 (0.183: above it dark ink beats white)
        // and the area is bright on average (mean over 0.40 behind the time, as the app's rule). The
        // boost then covers the name and status only, so the dark time and its halo sit on the
        // un-darkened photo.
        if let t = time, t.p95 > 0.183 {
            let textOnly = shaped(textRegion, amount: boost.amount)
            let unboosted = photoLuminance(photo, phase: phase, aspect: aspect, region: timeRegion, boost: textOnly)
            if (unboosted?.mean ?? t.mean) > 0.40 {
                return Backing(boost: textOnly, bright: true)
            }
        }
        return Backing(boost: boost, bright: false)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static var brightness: [String: (mean: Double, p95: Double)] = [:]

    /// The region's mean and 95th-percentile luminance as the card shows it: the photo filling the
    /// card, tinted as WidgetSky.look says and darkened by the scrim (with `boost`).
    private static func photoLuminance(_ photo: Photo, phase: WidgetSky.Phase, aspect: CGFloat, region: CGRect,
                                       boost: WidgetScrim.Boost) -> (mean: Double, p95: Double)? {
        let image = photo.image
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, aspect > 0 else { return nil }
        let look = WidgetSky.look(phase, nightPhoto: photo.isNight)
        let cacheKey = "\(photo.key)|\(photo.isNight)|\(phase)|\(Int(aspect * 4))|\(boost)|\(region.minX),\(region.minY),\(region.width),\(region.height)"
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
        let saturation = look.saturation
        let tint = look.shade
        var values: [Double] = []
        values.reserveCapacity(w * h)
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
                let k = WidgetScrim.remaining(u: u, v: v, boost: boost)
                values.append(luminance(r * tint.0 * k, g * tint.1 * k, b * tint.2 * k))
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        let result = (mean: values.reduce(0, +) / Double(values.count),
                      p95: values[min(values.count - 1, Int(Double(values.count) * 0.95))])
        lock.lock()
        if brightness.count > 120 { brightness.removeAll() }
        brightness[cacheKey] = result
        lock.unlock()
        return result
    }

    /// The fallback sky's gradient over the region, darkened by the scrim: its brightest sample.
    private static func skyLuminance(_ phase: WidgetSky.Phase, region: CGRect) -> Double {
        let (top, bottom) = WidgetSky.skyHex(phase)
        let a = DayColor.components(top), b = DayColor.components(bottom)
        var brightest = 0.0
        let rows = 8, cols = 8
        for row in 0..<rows {
            let v = Double(region.minY) + Double(region.height) * (Double(row) + 0.5) / Double(rows)
            for col in 0..<cols {
                let u = Double(region.minX) + Double(region.width) * (Double(col) + 0.5) / Double(cols)
                let k = WidgetScrim.remaining(u: u, v: v)
                brightest = max(brightest, luminance((a.0 + (b.0 - a.0) * v) * k, (a.1 + (b.1 - a.1) * v) * k,
                                                     (a.2 + (b.2 - a.2) * v) * k))
            }
        }
        return brightest
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

    /// Whether the city shows its night photo: the sun has set and sunrise is more than an hour
    /// away (the app's Sky.phase is .night). The hour before sunset, the hour before sunrise and
    /// the hour after it keep the day photo, warmly tinted.
    static func wantsNightPhoto(_ city: WidgetSnapshot.City, at date: Date) -> Bool {
        raw(city, at: date) == .night
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

    /// How a photo is shown: a real night photo as taken; a day photo as taken by day, warmly
    /// tinted in twilight and, only when the city has no night photo, darkened at night.
    static func look(_ phase: Phase, nightPhoto: Bool) -> (shade: (Double, Double, Double), saturation: Double) {
        if nightPhoto { return (shade: (1, 1, 1), saturation: 1) }
        return (shade: shadeComponents(phase), saturation: saturation(phase))
    }

    /// The day photo's tint: darker and cooler at night (only with no night photo), warmer in
    /// twilight, as it is by day.
    static func shadeComponents(_ phase: Phase) -> (Double, Double, Double) {
        switch phase {
        case .night: return (0.400, 0.459, 0.522)      // #667585, Two Degrees' overcast-day top
        case .twilight: return (0.941, 0.820, 0.714)   // #F0D1B6, its moon and sunset accents
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
        case .day: return (0x3D74B0, 0x1C3A5E)        // Two Degrees' clear day
        case .twilight: return (0x4F78A3, 0x24384F)   // its partly cloudy day
        case .night: return (0x141E3C, 0x0A0E1C)      // its clear night
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
        case .working: hex = 0x9AD3A8            // Two Degrees' mild green
        case .offHours: hex = 0xB9C3CF           // TileAccent.cloud
        case .weekend, .dayOff: hex = 0xF2C66D   // TileAccent.sunrise
        case .holiday: hex = 0xF39A72            // TileAccent.sunset
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

/// The card's scrim: black at 55% along the bottom, eased out by 70% of the way up, and a lighter
/// one from the left (35%, eased out by 60% across); eased stops, so no line shows across a bright
/// sky. On a bright photo (a day photo's sky or white facades behind the text) `boost` adds a flat
/// layer of black over the name, status and time, as much as the measured brightness behind them
/// needs (WidgetSkylines.backing); dark photos get none.
struct WidgetScrim: View {
    static let bottomOpacity = 0.55
    static let bottomReach = 0.70
    /// By distance from the bottom: the fraction of `bottomOpacity`.
    static let bottomStops: [(Double, Double)] = [(0, 1), (0.20, 0.80), (0.40, 0.42), (0.55, 0.14), (0.70, 0)]
    /// By distance from the left: the opacity.
    static let leftStops: [(Double, Double)] = [(0, 0.35), (0.30, 0.25), (0.45, 0.12), (0.60, 0)]
    /// The boost's feather, eased (smoothstep at quarters).
    static let featherStops: [(Double, Double)] = [(0, 0), (0.25, 0.156), (0.5, 0.5), (0.75, 0.844), (1, 1)]
    /// The boosts tried, smallest first (up to 0.55: enough for the white name on a day sky without
    /// turning the photo night-dark (0.65 for a night time, timeBoostSteps); a bright time switches
    /// to dark ink instead).
    static let boostSteps: [Double] = [0, 0.15, 0.3, 0.45, 0.55]
    /// For white digits on a partly lit area: one step further (0.65), covering the name and time.
    static let timeBoostSteps: [Double] = boostSteps + [0.65]

    /// The boost: `amount` of black, full from `top` (unit, top-left origin) down to the bottom and
    /// from the left edge to `right`, eased in over `featherV` above and `featherH` to the right.
    struct Boost: Equatable {
        var amount = 0.0
        var top = 1.0
        var right = 0.0
        var featherV = 0.0
        var featherH = 0.0

        func coverage(u: Double, v: Double) -> Double {
            let down: Double
            if v >= top { down = 1 }
            else if featherV > 0 { down = WidgetScrim.interpolate(WidgetScrim.featherStops, (v - (top - featherV)) / featherV) }
            else { down = 0 }
            let across: Double
            if u <= right { across = 1 }
            else if featherH > 0 { across = WidgetScrim.interpolate(WidgetScrim.featherStops, 1 - (u - right) / featherH) }
            else { across = 0 }
            return down * across
        }
    }

    var boost = Boost()

    /// Piecewise-linear through `stops` (as a gradient draws them), held flat outside them.
    static func interpolate(_ stops: [(Double, Double)], _ x: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 0..<(stops.count - 1) where x >= stops[i].0 && x <= stops[i + 1].0 {
            let span = stops[i + 1].0 - stops[i].0
            let t = span == 0 ? 1 : (x - stops[i].0) / span
            return stops[i].1 + (stops[i + 1].1 - stops[i].1) * t
        }
        return last.1
    }

    /// The light left at (u, v) of the card's unit square once the scrim is over it.
    static func remaining(u: Double, v: Double, boost: Boost = Boost()) -> Double {
        let up = bottomOpacity * interpolate(bottomStops, 1 - v)
        let extra = boost.amount * boost.coverage(u: u, v: v)
        let across = interpolate(leftStops, u)
        return (1 - up) * (1 - extra) * (1 - across)
    }

    private var bottomGradient: [Gradient.Stop] {
        Self.bottomStops.map { stop -> Gradient.Stop in
            Gradient.Stop(color: Color.black.opacity(Self.bottomOpacity * stop.1), location: CGFloat(stop.0))
        }
    }

    private var leftGradient: [Gradient.Stop] {
        Self.leftStops.map { stop -> Gradient.Stop in
            Gradient.Stop(color: Color.black.opacity(stop.1), location: CGFloat(stop.0))
        }
    }

    /// Clear above the boost, eased in over its feather, full to the bottom.
    private var boostDown: [Gradient.Stop] {
        var stops: [Gradient.Stop] = Self.featherStops.map { stop -> Gradient.Stop in
            let location = boost.top - boost.featherV + boost.featherV * stop.0
            return Gradient.Stop(color: Color.black.opacity(stop.1), location: CGFloat(location))
        }
        stops.append(Gradient.Stop(color: Color.black, location: 1))
        return stops
    }

    /// Full from the left edge, eased out over the feather to the right of the text.
    private var boostAcross: [Gradient.Stop] {
        var stops: [Gradient.Stop] = [Gradient.Stop(color: Color.black, location: 0)]
        for stop in Self.featherStops {
            let opacity = Self.interpolate(Self.featherStops, 1 - stop.0)
            let location = boost.right + boost.featherH * stop.0
            stops.append(Gradient.Stop(color: Color.black.opacity(opacity), location: CGFloat(location)))
        }
        return stops
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: bottomGradient, startPoint: .bottom, endPoint: .top)
            if boost.amount > 0 {
                Color.black.opacity(boost.amount)
                    .mask(LinearGradient(stops: boostDown, startPoint: .top, endPoint: .bottom))
                    .mask(LinearGradient(stops: boostAcross, startPoint: .leading, endPoint: .trailing))
            }
            LinearGradient(stops: leftGradient, startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// A city's photo filling the space, or its sky when there's no photo, with the scrim over it. A
/// night photo shows as taken; a day photo as taken by day, warmly tinted in twilight and darkened
/// only at night when the city has no night photo. Crossfades when the photo changes.
struct WidgetCityBackdrop: View {
    let city: WidgetSnapshot.City
    let date: Date
    let photo: WidgetSkylines.Photo?
    var boost = WidgetScrim.Boost()

    var body: some View {
        let phase = WidgetSky.phase(city, at: date)
        ZStack {
            if let photo {
                let look = WidgetSky.look(phase, nightPhoto: photo.isNight)
                Color.clear
                    .overlay {
                        Image(decorative: photo.image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .saturation(look.saturation)
                            .colorMultiply(Color(red: look.shade.0, green: look.shade.1, blue: look.shade.2))
                    }
                    .clipped()
                    .id(photo.key)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: WidgetSky.sky(phase), startPoint: .top, endPoint: .bottom)
            }
            WidgetScrim(boost: boost)
        }
        .animation(.easeInOut(duration: 0.6), value: photo?.key)
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
                // Never under 13 pt, as the app's (11 pt read as 7.7 pt of ink beside the rows' 17 pt time).
                let suffixSize = max(13, size * 0.45)
                outlined(Text("\u{2009}" + suffix).font(.system(size: suffixSize, weight: .semibold)),
                         width: suffixSize / 24)
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
            t.foregroundStyle(bright ? WidgetTone.ink : Color.white)
        }
    }
}

/// The app's status pill, small: an icon and the status in its colour on a dark backing (at least
/// 11 pt, on black at 65% (was 50%) so a bright photo can't wash out "Off hours").
struct WidgetStatusPill: View {
    let status: WidgetWorkStatus
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.system(size: size * 0.9, weight: .semibold))
            Text(status.title)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.black.opacity(0.65)))
        .overlay(Capsule().strokeBorder(status.color.opacity(0.5), lineWidth: 1))
    }
}

/// The city name on a photo, with a soft shadow.
private func widgetCityName(_ name: String, size: CGFloat) -> some View {
    Text(name)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.85)   // 13 pt never under 11 pt
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
        // An outline only: a white wash or glow lightened the middle tile under it (12 PM fell to
        // 4.3:1), the tile people read most.
        return shape
            .strokeBorder(Color.white.opacity(0.62), lineWidth: Self.stroke)
            .frame(width: tileWidth + 2 * Self.outset, height: max(1, bottom - top))
            .offset(x: middleLeft - Self.outset, y: top)
    }

    private func row(_ city: WidgetSnapshot.City, width: CGFloat, height: CGFloat,
                     tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let photo = WidgetSkylines.photo(for: city, at: date)
        let phase = WidgetSky.phase(city, at: date)
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        let clockSize = min(34, max(17, (height * 0.28).rounded()))
        // About where the name (and status) and the time above them sit: bottom left.
        let textHeight: CGFloat = status == nil ? 17 : 33
        let clockBottom = height - Self.bottomPadding - textHeight
        let textWidth = min(0.45, max(clockSize * 3, 120) / max(width, 1))
        let textRegion = CGRect(x: Self.sidePadding / max(width, 1), y: max(0, clockBottom) / height,
                                width: textWidth, height: min(1, textHeight / height))
        // The digits and the 13 pt AM/PM after them.
        let timeRegion = CGRect(x: Self.sidePadding / max(width, 1), y: max(0, clockBottom - clockSize * 1.2) / height,
                                width: min(0.55, (clockSize * 2.9 + 30) / max(width, 1)), height: min(1, clockSize * 1.2 / height))
        let backing = WidgetSkylines.backing(photo, phase: phase, size: CGSize(width: width, height: height),
                                             textRegion: textRegion, timeRegion: timeRegion)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        // AM/PM goes under the hour whenever the tile is tall enough (inline "11 AM" filled a 40 pt
        // tile edge to edge), and always on narrow tiles and in half-hour zones ("9:30" over "AM"),
        // so every row, Mumbai's included, reads the same two-line way.
        let halfHour = zone.secondsFromGMT(for: date) % 3600 != 0
        let stacked = !snapshot.use24h && (tileHeight >= 31 || tileWidth < 39 || halfHour)
        let digitSize: CGFloat = stacked && tileHeight >= 34 ? 16 : 14
        return ZStack(alignment: .bottomLeading) {
            WidgetCityBackdrop(city: city, date: date, photo: photo, boost: backing.boost)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: clockSize, bright: backing.bright)
                        .widgetAccentable()
                        .layoutPriority(1)
                    ViewThatFits(in: .vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            widgetCityName(city.name, size: 13)
                            if let status { WidgetStatusPill(status: status) }
                        }
                        widgetCityName(city.name, size: 13)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                HStack(spacing: Self.tileGap) {
                    ForEach(-1...1, id: \.self) { k in
                        WidgetPhotoTile(snapshot: snapshot, city: city, zone: zone,
                                        start: anchor.addingTimeInterval(Double(k) * 3600), center: k == 0,
                                        stacked: stacked, digitSize: digitSize)
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
/// working hours), the hour with AM/PM under it when `stacked` (tiles tall enough, narrow tiles and
/// "9:30" zones; as the app's), after it ("9 AM") only on short tiles, and a mark where a new day starts.
struct WidgetPhotoTile: View {
    let snapshot: WidgetSnapshot
    let city: WidgetSnapshot.City
    let zone: TimeZone
    let start: Date
    let center: Bool
    var stacked = false
    var digitSize: CGFloat = 14

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        let newDay = !calendar.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
        let dim = WidgetWorkStatus.dims(city, snapshot: snapshot, hourStart: start)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let suffix: String? = snapshot.use24h ? nil : (hour < 12 ? "AM" : "PM")
        return Group {
            if stacked {
                // The hour over AM/PM, as the app's tiles: only the digits may shrink (to 0.88, 0.85 for half hours);
                // AM/PM stays 12 pt.
                VStack(spacing: -1) {
                    label(hour: hour, minute: minute)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(minute != 0 ? 0.85 : 0.88)
                    if let suffix {
                        Text(suffix)
                            .font(Self.suffixFont)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                    }
                }
            } else {
                // Inline ("9 AM"): 24-hour labels, and the fallback for tiles under 31 pt tall,
                // where shrinking the whole label (to 0.85) beats truncating it.
                (suffix.map { label(hour: hour, minute: minute) + Text("\u{2009}" + $0).font(Self.suffixFont) }
                    ?? label(hour: hour, minute: minute))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .foregroundStyle(style.text)
        // Clear of the tile's rounded corners: 6 pt each side (was 1), 2 pt for "12:30" (digits may shrink to 0.85).
        .padding(.horizontal, stacked ? (minute != 0 ? 2 : 6) : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Off-hours tiles are darkened, never see-through (was 88% opacity: the photo showed
        // through behind the numerals), as the app's.
        .background(shape.fill(dim ? DayColor.offHoursFill(at: Double(hour) + Double(minute) / 60) : style.fill))
        // Night and off-hours tiles are near-black: a hairline keeps the row reading as tiles on a
        // dark night photo, as the app's HourTiles.
        .overlay(shape.strokeBorder(Color.white.opacity(dim || hour < 6 || hour >= 21 ? 0.16 : 0), lineWidth: 0.5))
        .overlay(alignment: .leading) {
            if newDay {
                Capsule().fill(WidgetTone.midnight)
                    .frame(width: 2).padding(.vertical, 6).offset(x: -(WidgetPhotoRows.tileGap / 2 + 1))
            }
        }
    }

    /// AM/PM and half-hour minutes: 12 pt (was 11), a step above Apple's 11 pt minimum.
    private static let suffixFont = Font.system(size: 12, weight: .semibold)

    /// "9" or "09" (`digitSize`: 16 pt over AM/PM, else 14), with ":30" at 12 pt in half-hour zones.
    private func label(hour: Int, minute: Int) -> Text {
        var text = Text(snapshot.use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)")
            .font(.system(size: minute != 0 ? 14 : digitSize, weight: center ? .semibold : .medium))
        if minute != 0 {
            text = text + Text(":" + String(format: "%02d", minute)).font(.system(size: 12, weight: .medium))
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

    /// The photo and how its scrim backs the text, shared with the container background
    /// (WidgetContainerBackground) so both draw the same photo and the same scrim.
    static func backdrop(snapshot: WidgetSnapshot, city: WidgetSnapshot.City, date: Date)
        -> (photo: WidgetSkylines.Photo?, backing: WidgetSkylines.Backing) {
        let photo = WidgetSkylines.photo(for: city, at: date)
        let hasStatus = WidgetWorkStatus.of(city, snapshot: snapshot, at: date) != nil
        let backing = WidgetSkylines.backing(
            photo, phase: WidgetSky.phase(city, at: date), size: CGSize(width: 160, height: 160),
            textRegion: CGRect(x: 0.08, y: hasStatus ? 0.66 : 0.74, width: 0.62, height: hasStatus ? 0.26 : 0.16),
            timeRegion: CGRect(x: 0.08, y: hasStatus ? 0.4 : 0.5, width: 0.6, height: 0.25))
        return (photo, backing)
    }

    var body: some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        let bright = Self.backdrop(snapshot: snapshot, city: city, date: date).backing.bright
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: 34, bright: bright)
                .widgetAccentable()
            widgetCityName(city.name, size: 14)
            if let status {
                WidgetStatusPill(status: status, size: 12)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
#endif
