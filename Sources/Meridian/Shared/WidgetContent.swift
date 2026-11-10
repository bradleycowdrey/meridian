import SwiftUI
import WidgetKit
#if os(iOS)
import ImageIO
import UIKit
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

/// Sky through the day, on iPhone and Mac alike: Two Degrees' sky (navy night, blue dawn and dusk,
/// sky blue by day).
enum DayColor {
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

    /// On a widget, night tiles are lifted just above the widget's own background so every hour
    /// reads as a tile (the darkest hours otherwise vanish into it).
    static func style(at hour: Double, lifted: Bool) -> (fill: Color, text: Color) {
        guard lifted else { return style(at: hour) }
        var rgb = rgbAt(hour)
        let floor = components(liftFloor)
        rgb = (max(rgb.0, floor.0), max(rgb.1, floor.1), max(rgb.2, floor.2))
        // Every sky tone is dark enough for white text (the brightest, #3A6699, is 5.9:1).
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), Color.white)
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
        // Every sky tone is dark enough for white text (the brightest, #3A6699, is 5.9:1).
        let text = Color.white
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), text)
    }

    /// An hour outside working hours, as the app's tiles (HourTiles.offHours): the hour's sky at 30%
    /// of its luminance (was 55%), capped at `offHoursCap` and never darker than the night tile
    /// (#0A0E1C), same hue, fully opaque, so the photo never shows through behind the numerals. At 55%
    /// a midday off tile (42,76,116) sat 1.48:1 from the working tile (58,102,153); now (10,24,41) is
    /// 3.2:1 (WCAG 1.4.11), white on it 17.8:1. The cap is 0.006, as the app's HourTiles.offHoursCap,
    /// so the midday working tile (0.127) stands 3.2:1 from it.
    static let offHoursFactor = 0.30
    static let offHoursFloor = 0.0048
    static let offHoursCap = 0.006

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
        let k = min(max(min(luminance, offHoursFloor), luminance * offHoursFactor), offHoursCap) / luminance
        return Color(red: encoded(lr * k), green: encoded(lg * k), blue: encoded(lb * k))
    }

    /// An hour inside working hours (when the app highlights them), as the app's HourTiles.legible:
    /// the hour's sky, same hue, its luminance held between `workingFloor` and `workingCap`. The
    /// shoulder hours (8 to 9.5 h, 17.5 to 19 h) come from the ramp's darker steps: 9 AM was
    /// (44,83,134), L 0.084, only 2.4:1 from the off tile beside it (L 0.006). Floored at 0.12 it
    /// stands 3.05:1 from every off tile (WCAG 1.4.11) and white on it stays 6.2:1.
    static let workingFloor = 0.12
    static let workingCap = 0.14

    static func workingFill(at hour: Double) -> Color {
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
        let k = min(max(luminance, workingFloor), workingCap) / luminance
        return Color(red: encoded(lr * k), green: encoded(lg * k), blue: encoded(lb * k))
    }

    fileprivate static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// The brand palette, restated here so the widget extension doesn't need the app's Palette.
/// Two Degrees' black (near-black on the Mac), white at its opacities and its sunrise accent.
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
    /// Mac: the panel's near-black (#0B0C0F) and white at the panel's opacities.
    static let bg = tone(0x0B0C0F)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.85)
    static let muted = Color.white.opacity(0.6)
    static let faint = Color.white.opacity(0.46)
    static let cream = Color.white
    /// The new-day marker on the hour tiles (gold, as the iPhone's).
    static let midnight = tone(0xF2C66D)
    /// No crimson on the Mac either: kept as a name for shared code, it is the midnight accent.
    static let crimson = midnight
    /// The hairline between widget cells and under the large header.
    static let divider = Color.white.opacity(0.18)
    #endif

    private static func tone(_ hex: UInt32) -> Color {
        let c = DayColor.components(hex)
        return Color(red: c.0, green: c.1, blue: c.2)
    }
}

/// The widget's background. iPhone: Two Degrees' neutral evening sky. Mac: the panel's near-black.
struct MeridianWidgetBackground: View {
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        #if os(iOS)
        LinearGradient(colors: [WidgetTone.skyTop, WidgetTone.skyBottom], startPoint: .top, endPoint: .bottom)
        #else
        WidgetTone.bg
        #endif
    }
}

/// The widget's container background: the small widget is its city's skyline photo, filling it (as
/// the app's cards are; on the Mac under a dark scrim); otherwise MeridianWidgetBackground.
struct WidgetContainerBackground: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily
    var isPreview = false

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        #if os(iOS)
        if family == .systemSmall, renderingMode == .fullColor, let city = snapshot.cities.first {
            WidgetCityBackdrop(city: city, date: date, photo: WidgetSkylines.photo(for: city, at: date))
        } else {
            MeridianWidgetBackground()
        }
        #else
        if family == .systemSmall, renderingMode == .fullColor, let city = snapshot.cities.first {
            MacSkylineBackdrop(name: city.name, timeZoneID: city.timeZoneID, latitude: city.latitude,
                               longitude: city.longitude, date: date, maxPixel: 600, synchronous: true)
                .overlay(WidgetClockView.photoScrim)
        } else {
            MeridianWidgetBackground()
        }
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
            .dynamicTypeSize(...DynamicTypeSize.xLarge)   // as the widget root (iPhone; WidgetType.scale is 1 on the Mac)
    }
}

/// The reader's text size, for widget text set in points. iPhone: the default (Large) and smaller
/// keep the designed sizes (nothing goes under 11 pt); larger sizes grow names, captions and status
/// by 10%. The widget root caps Dynamic Type at xLarge, so the fixed tiles and rows still hold. The
/// Mac's sizes are fixed.
enum WidgetType {
    static func scale(_ size: DynamicTypeSize) -> CGFloat {
        #if os(iOS)
        return size > .large ? 1.1 : 1
        #else
        return 1
        #endif
    }
}

/// A widget time: the digits, then AM/PM smaller and raised (Two Degrees' reading style; on the Mac
/// AM/PM is never below 11 pt).
/// iPhone: AM/PM never below 12 pt (was 11; Lock Screen vibrancy lowers contrast), and raised only beside big digits (22 pt and up); beside
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
            .font(.system(size: max(12, size * 0.42), weight: .semibold))
            .baselineOffset(size >= 22 ? size * 0.3 : 0)
        #else
        return main + Text("\u{2009}" + suffix)
            .font(.system(size: max(11, size * 0.42), weight: .semibold))
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Names and captions grow with the reader's text size on iPhone (1 on the Mac).
    private var typeScale: CGFloat { WidgetType.scale(typeSize) }

    /// Accented, vibrant (Lock Screen, tinted Home Screen) or clear (StandBy): no opaque blocks,
    /// no brand colours; shapes and text in the system's primary colour.
    private var tinted: Bool {
        renderingMode != .fullColor || (!showsBackground && !isPreview)
    }

    /// The hairline between the two medium cells and under the large header.
    #if os(iOS)
    private static let ruleTone = WidgetTone.divider
    #else
    private static let ruleTone = WidgetTone.divider
    #endif
    private var rule: Color { tinted ? Color.primary.opacity(0.3) : Self.ruleTone }

    /// The "Now", "+1 hr" labels and the tiles' text: nothing under 11 pt (Apple's minimum).
    #if os(iOS)
    private static let labelSize: CGFloat = 11
    private static let tileSize: CGFloat = 13
    private static let tileSmallSize: CGFloat = 12
    private static let tileMinuteSize: CGFloat = 12
    private static let tileSmallWeight: Font.Weight = .semibold
    private static let tileMinScale: CGFloat = 0.85   // digits only; AM/PM never shrinks
    /// City names and zone captions never scale under 11 pt on iPhone.
    private static let nameMinScale: CGFloat = 0.9
    private static let largeNameMinScale: CGFloat = 0.9
    private static let captionMinScale: CGFloat = 1
    #else
    private static let labelSize: CGFloat = 11
    private static let tileSize: CGFloat = 13
    private static let tileSmallSize: CGFloat = 11
    private static let tileMinuteSize: CGFloat = 11
    private static let tileSmallWeight: Font.Weight = .semibold
    private static let tileMinScale: CGFloat = 0.85   // digits only; AM/PM never shrinks
    private static let nameMinScale: CGFloat = 0.9
    private static let largeNameMinScale: CGFloat = 0.9
    private static let captionMinScale: CGFloat = 1
    #endif
    /// "Now" labels and outlines: white in full colour.
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
            WidgetPhotoRows(snapshot: snapshot, cities: cities, date: date, maxCities: cityLimit)
        }
    }
    #endif

    /// A stacked half-hour tile's "8:30" at fixed sizes, one ViewThatFits step.
    private func halfHourDigits(_ hour: Int, _ minute: Int, hourSize: CGFloat, minuteSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(hour % 12 == 0 ? 12 : hour % 12)")
                .font(.system(size: hourSize, weight: .medium))
            Text(":" + String(format: "%02d", minute))
                .font(.system(size: minuteSize, weight: .medium))
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The Mac's face (its cities on their photos in full colour), and the iPhone's in tinted and clear modes.
    private var classicFace: some View {
        Group {
            if cities.isEmpty {
                VStack(spacing: 4) {
                    // Both grow with the reader's text size on iPhone (typeScale is 1 on the Mac).
                    Text("No cities yet")
                        .font(.system(size: 13 * typeScale, weight: .semibold))
                    Text("Add cities in Meridian")
                        .font(.system(size: 11 * typeScale, weight: .medium))
                        .foregroundStyle(WidgetTone.muted)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch family {
                case .systemLarge:
                    strip
                case .systemMedium:
                    #if os(iOS)
                    HStack(alignment: .top, spacing: 14) {
                        cityCell(cities[0], timeSize: 34).frame(maxWidth: .infinity, alignment: .leading)
                        if cities.count > 1 {
                            Rectangle().fill(rule).frame(width: 0.5)
                            cityCell(cities[1], timeSize: 34).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                    #else
                    // Mac: one or two city rows filling the widget, as the large's.
                    strip
                    #endif
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

    #if os(iOS)
    /// A new day starts there in the hour from `start` (usually 00:00; some clock changes skip it).
    private static func phoneStartsNewDay(_ start: Date, zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return !calendar.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
    }

    private func cityCell(_ city: WidgetSnapshot.City, timeSize: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        return VStack(alignment: .leading, spacing: 0) {
            Text(city.name)
                .font(.system(size: 13 * typeScale, weight: .semibold))
                .foregroundStyle(WidgetTone.primary)
                .lineLimit(1)
                .minimumScaleFactor(Self.nameMinScale)
            WidgetClockText.text(clock, suffix: suffix, size: timeSize)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption(zone))
                .font(.system(size: 11 * typeScale, weight: .medium))
                .foregroundStyle(WidgetTone.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(Self.captionMinScale)
            Spacer(minLength: 4)
            // The hour before, now (outlined) and the hour after, each labelled.
            HStack(spacing: 4) {
                ForEach(-1...1, id: \.self) { k in
                    let start = anchor.addingTimeInterval(Double(k) * 3600)
                    // A new day: its weekday ("WED") is the tag above the tile, in the label's place
                    // 3 pt above it (these 22 pt tiles have no other room); the tile reads "12 AM".
                    let newDay = Self.phoneStartsNewDay(start, zone: zone)
                    let label: String = k == 0 ? "Now" : (k > 0 ? "+1 hr" : "−1 hr")
                    VStack(spacing: 3) {
                        Text(newDay ? WidgetPhotoTile.weekday(start, zone: zone, format: "EEE").uppercased() : label)
                            .font(.system(size: Self.labelSize, weight: k == 0 || newDay ? .semibold : .medium))
                            .tracking(newDay ? 0.3 : 0)
                            .foregroundStyle(k == 0 || newDay ? nowTone : WidgetTone.muted)
                            .lineLimit(1)
                            .accessibilityLabel(newDay ? WidgetPhotoTile.weekday(start, zone: zone, format: "EEEE") : label)
                        tile(start, zone: zone)
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
    #else
    /// The Now tile's scale on the Mac's widgets (the panel's is 1.13).
    private static let nowScale: CGFloat = 1.12

    /// Full colour on the Mac: cities sit on their skyline photos (tinted and clear modes draw none).
    private var photos: Bool { !tinted }

    /// The only darkening left on a photo: black at 45% at the text's edge, easing (smoothstep, no
    /// visible band) to nothing at `end` (0...1 along the gradient), and nothing after it.
    static func macFade(end: CGFloat) -> [Gradient.Stop] {
        let end = min(1, max(0.01, end))
        return (0...8).map { i in
            let t = Double(i) / 8
            let eased = t * t * (3 - 2 * t)
            return Gradient.Stop(color: Color.black.opacity(0.45 * (1 - eased)), location: end * CGFloat(t))
        }
    }

    /// The small widget's photo: darkened only behind the name, time and caption at its top (45%
    /// at the top edge easing to none 56% down, where the text ends); the rest is the photo as it is.
    static let photoScrim = LinearGradient(stops: macFade(end: 0.56), startPoint: .top, endPoint: .bottom)

    /// Small text on a photo (the caption, the small widget's hour labels): a dark chip behind it,
    /// black at 55%, so white keeps 4.7:1 or more even on a pure white photo.
    static let chipTone = Color.black.opacity(0.55)

    /// The outline around the Now tiles: a white line with a thin dark edge, no fill (tinted modes:
    /// one line in the system's colour).
    private func nowOutline(width: CGFloat, height: CGFloat, radius: CGFloat, tintedTone: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if tinted {
                shape.stroke(tintedTone, lineWidth: 1.5)
            } else {
                shape.stroke(Color.black.opacity(0.6), lineWidth: 2.5)
                shape.stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            }
        }
        .widgetAccentable()
        .frame(width: width, height: height)
    }

    /// A new day starts in the hour from `moment` there (usually 00:00, but some clock changes skip midnight).
    private func macStartsNewDay(_ moment: Date, zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return !calendar.isDate(moment, inSameDayAs: moment.addingTimeInterval(-3600))
    }

    /// "WED": the weekday there, for the new day's tag.
    private static func macWeekday(_ moment: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: moment).uppercased()
    }

    /// The new day's weekday tag, as on the iPhone (HourTiles' DayTag): 11 pt semibold caps, gold on
    /// a dark pill (tinted modes: the word alone, in the system's colour), centred on its tile and
    /// never wider than it (5 pt each side of the word, down to 3). The tile itself reads "12", "AM"
    /// (or "00") like its neighbours.
    private func macDayTag(_ moment: Date, zone: TimeZone, height: CGFloat) -> some View {
        let word = Self.macWeekday(moment, zone: zone)
        return ViewThatFits(in: .horizontal) {
            macDayPill(word, padding: 5, height: height)
            macDayPill(word, padding: 4, height: height)
            macDayPill(word, padding: 3, height: height)
        }
    }

    private func macDayPill(_ word: String, padding: CGFloat, height: CGFloat) -> some View {
        Text(word)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.3)
            .lineLimit(1)
            .foregroundStyle(tinted ? Color.primary : WidgetTone.midnight)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background {
                if !tinted { Capsule().fill(Color.black.opacity(0.55)) }
            }
            .fixedSize()
    }

    /// The weekday tag's top (from its tile's top) and height where there is no room for it above
    /// the tile: 15 pt high from `top`, or higher (never above `limit`) to stay 1.5 pt clear of the
    /// digits; 13 pt high where that needs it.
    private static func macTuckedTag(tile: CGFloat, stacked: Bool, now: Bool,
                                     top: CGFloat, limit: CGFloat) -> (y: CGFloat, height: CGFloat) {
        // From the tile's centre up to the top of its digits: 15 pt digits over 11 pt AM/PM, or one
        // 13 pt line (the Now tile's are scaled with it).
        let digitsTop = tile / 2 - (stacked ? 11.3 : 4.6) * (now ? nowScale : 1)
        for height: CGFloat in [15, 13] {
            let y = min(top, digitsTop - 1.5 - height)
            if y >= limit { return (y, height) }
        }
        return (limit, 13)
    }

    /// The small widget's weekday tag. The Now tile's is always 13 pt high and 2 pt above its
    /// outline's top line (the line's edge is 4.5 pt above the larger tile); where the labels cannot
    /// move up (not `lifted`) it takes the "Now" label's place. Other tiles: 3 pt above the tile
    /// when `lifted`, otherwise across the tile's top edge, under the label's baseline.
    private static func macCellTag(stacked: Bool, now: Bool, lifted: Bool) -> (y: CGFloat, height: CGFloat) {
        if now { return (-(34 * (nowScale - 1) / 2 + 4.5 + 2 + 13), 13) }
        guard lifted else { return macTuckedTag(tile: 34, stacked: stacked, now: false, top: 2, limit: -8) }
        return (-18, 15)
    }

    /// Where a tile in the widget starts a new day (in any of its cities, so the cells' labels stay
    /// level), the "Now" and "+1 hr" labels move up to leave room for the weekday tag above the tile;
    /// if the widget is too short for that, the tag sits across the tile's top edge (the Now tile's
    /// in place of its "Now" label).
    private func cityCell(_ city: WidgetSnapshot.City, timeSize: CGFloat) -> some View {
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        let tagged = cities.contains { other in
            let zone = TimeZone(identifier: other.timeZoneID) ?? .current
            return (-1...1).contains { macStartsNewDay(anchor.addingTimeInterval(Double($0) * 3600), zone: zone) }
        }
        return GeometryReader { geo in
            // Room either side of the Now tile: 6.5 pt between the (larger) Now tile and each
            // neighbour (3 pt more than before), whatever the widget's width; the outline's line runs
            // down the middle of it, 2 pt clear of both tiles.
            let grow: CGFloat = (Self.nowScale - 1) / 2
            let tileWidth: CGFloat = max(1, (geo.size.width - 13) / (3 + 2 * grow))
            let spacing: CGFloat = 6.5 + tileWidth * grow
            ViewThatFits(in: .vertical) {
                cityCellBody(city, timeSize: timeSize, lifted: tagged, spacing: spacing)
                cityCellBody(city, timeSize: timeSize, lifted: false, spacing: spacing)
            }
        }
    }

    private func cityCellBody(_ city: WidgetSnapshot.City, timeSize: CGFloat, lifted: Bool,
                              spacing: CGFloat) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        // On the photo the small text is white on a dark chip (tinted modes: the plain muted text).
        let quiet = photos ? WidgetTone.primary : WidgetTone.muted
        return VStack(alignment: .leading, spacing: 0) {
            Text(city.name)
                .font(.system(size: 13 * typeScale, weight: .semibold))
                .foregroundStyle(WidgetTone.primary)
                .lineLimit(1)
                .minimumScaleFactor(Self.nameMinScale)
                .macHalo(photos)
            WidgetClockText.text(clock, suffix: suffix, size: timeSize)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .macHalo(photos)
            Text(caption(zone))
                .font(.system(size: 11 * typeScale, weight: photos ? .semibold : .medium))
                .foregroundStyle(quiet)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(Self.captionMinScale)
                .padding(.horizontal, photos ? 6 : 0)
                .padding(.vertical, photos ? 1 : 0)
                .background { if photos { Capsule().fill(Self.chipTone) } }
            Spacer(minLength: lifted ? 0 : 2)
            // The hour before, now (larger, outlined) and the hour after, each labelled.
            HStack(spacing: spacing) {
                ForEach(-1...1, id: \.self) { k in
                    let start = anchor.addingTimeInterval(Double(k) * 3600)
                    VStack(spacing: lifted ? 24 : 8) {
                        Text(k == 0 ? "Now" : (k > 0 ? "+1 hr" : "−1 hr"))
                            .font(.system(size: Self.labelSize, weight: k == 0 || photos ? .semibold : .medium))
                            .foregroundStyle(k == 0 ? nowTone : quiet)
                            .lineLimit(1)
                            .fixedSize()
                            // On the photo: a dark chip behind the label (drawn past it, so the layout holds).
                            .background { if photos { Capsule().fill(Self.chipTone).padding(.horizontal, -5) } }
                            // Too short to move the labels up: the Now tile's weekday tag takes this place.
                            .opacity(!lifted && k == 0 && macStartsNewDay(start, zone: zone) ? 0 : 1)
                        tile(start, zone: zone, stacked: !snapshot.use24h)
                            .frame(height: 34)
                            .scaleEffect(k == 0 ? Self.nowScale : 1)
                            .overlay {
                                if k == 0 {
                                    // Concentric with the Now tile, its line midway to the neighbours
                                    // (3.25 pt from each: 2 pt clear either side of the 2.5 pt line).
                                    GeometryReader { geo in
                                        nowOutline(width: geo.size.width * Self.nowScale + 6.5,
                                                   height: geo.size.height * Self.nowScale + 6.5,
                                                   radius: 6 * Self.nowScale + 3.25,
                                                   tintedTone: Color.primary)
                                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                    }
                                }
                            }
                            .overlay(alignment: .top) {
                                // A new day: its weekday tag (not scaled with the Now tile).
                                if macStartsNewDay(start, zone: zone) {
                                    let tag = Self.macCellTag(stacked: !snapshot.use24h, now: k == 0, lifted: lifted)
                                    macDayTag(start, zone: zone, height: tag.height).offset(y: tag.y)
                                }
                            }
                    }
                }
            }
        }
    }
    #endif

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

    #if os(iOS)
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
                                .font(.system(size: 13 * typeScale, weight: .semibold))
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
                                    .font(.system(size: 11 * typeScale, weight: .medium))
                                    .foregroundStyle(WidgetTone.muted)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(Self.captionMinScale)
                            }
                        }
                        .frame(width: labelWidth - 6, alignment: .leading)
                        .padding(.trailing, 6)

                        ForEach(-half...half, id: \.self) { k in
                            let start = anchor.addingTimeInterval(Double(k) * 3600)
                            let stacked = !snapshot.use24h && rowHeight >= 34
                            tile(start, zone: zone, stacked: stacked)
                                .frame(width: pitch - gap, height: rowHeight)
                                .overlay(alignment: .top) {
                                    // A new day: its weekday tag. The tiles fill their rows, so it sits
                                    // inside the tile's top edge, above the digits (tinted modes: the
                                    // word alone, in the system's colour); the tile reads "12", "AM".
                                    if Self.phoneStartsNewDay(start, zone: zone) {
                                        let roomy = (rowHeight - (stacked ? 32 : 16)) / 2 >= 17
                                        Text(WidgetPhotoTile.weekday(start, zone: zone, format: "EEE").uppercased())
                                            .font(.system(size: 11, weight: .semibold))
                                            .tracking(0.3)
                                            .lineLimit(1)
                                            .foregroundStyle(Color.primary)
                                            .frame(height: roomy ? 15 : 13)
                                            .fixedSize()
                                            .offset(y: roomy ? 2 : 1)
                                            .accessibilityLabel(WidgetPhotoTile.weekday(start, zone: zone, format: "EEEE"))
                                    }
                                }
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
    #else
    /// Mac (medium and large): each city a row, a card filled with its photo, laid out as the name,
    /// time and caption, then clear space where the city shows, then the hour tiles; the Now tiles
    /// larger, with room either side and one outline running down every row. The rows share the
    /// widget's whole height, and their contents grow with them when there are fewer cities.
    private var strip: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let headerHeight: CGFloat = 16
            let rows = max(cities.count, 1)
            let rowHeight: CGFloat = max(1, (geo.size.height - headerHeight - gap * CGFloat(rows)) / CGFloat(rows))
            // A row's height when the widget is full (large: five cities, medium: two): the designed look.
            let fullHeight: CGFloat = max(1, (geo.size.height - headerHeight - gap * CGFloat(cityLimit)) / CGFloat(cityLimit))
            let stretch: CGFloat = max(1, rowHeight / fullHeight)
            let textScale: CGFloat = min(1.25, stretch)
            let nameSize: CGFloat = 13 * textScale
            let captionSize: CGFloat = 11 * textScale
            // The time: 22 pt in a full widget of the usual size (a little less in a shorter one,
            // never under 17 pt), up to 1.5 times that in taller rows.
            let timeBase: CGFloat = 22 * min(1, fullHeight / 61.6)
            let timeSize: CGFloat = max(17, timeBase * min(1.5, stretch))
            let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
            let half = columns / 2
            // The tiles: whole points wide, from the widget's width; 6 pt inside a full widget's
            // rows, and up to 1.4 times that height in taller ones.
            let tw: CGFloat = min(46, max(40, geo.size.width * 0.136)).rounded(.down)
            let th: CGFloat = max(1, min(rowHeight - 12, (fullHeight - 12) * 1.4))
            // Room either side of the Now tile: 8 pt between the (larger) Now tile and each
            // neighbour (3 pt more than before); the outline's line runs down the middle of it,
            // 2.75 pt clear of both tiles.
            let grow: CGFloat = (Self.nowScale - 1) / 2
            let nowGap: CGFloat = 8
            let spacing: CGFloat = nowGap + tw * grow
            let tilesWidth: CGFloat = tw * CGFloat(columns) + spacing * CGFloat(columns - 1)
            // The name, time and caption: compact, wider with the larger text; then the clear space,
            // 40 pt or more where the widget has it.
            let room: CGFloat = max(0, geo.size.width - tilesWidth)
            let textWidth: CGFloat = max(min(104, room), min(104 * textScale, room - 40))
            let clear: CGFloat = max(0, room - textWidth)
            let inset: CGFloat = nowGap / 2
            let outlineWidth: CGFloat = tw * Self.nowScale + 2 * inset
            let outlineHeight: CGFloat = CGFloat(rows - 1) * (rowHeight + gap) + th * Self.nowScale + 2 * inset
            let outlineX: CGFloat = textWidth + clear + CGFloat(half) * (tw + spacing) + (tw - outlineWidth) / 2
            let tileTop: CGFloat = headerHeight + gap + (rowHeight - th) / 2
            let outlineY: CGFloat = tileTop - th * grow - inset
            // The card reaches 6 pt past the row on each side. Its photo's centre sits in the middle
            // of the clear space; the only darkening is behind the text, gone where the text ends.
            let cardWidth: CGFloat = geo.size.width + 12
            let focus: CGFloat = 6 + textWidth + clear / 2
            let scrim = LinearGradient(stops: Self.macFade(end: (6 + textWidth) / cardWidth),
                                       startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: spacing) {
                    Color.clear.frame(width: max(0, textWidth + clear - spacing), height: 1)
                    ForEach(-half...half, id: \.self) { k in
                        Text(k == 0 ? "Now" : (k > 0 ? "+\(k) hr" : "−\(-k) hr"))
                            .font(.system(size: Self.labelSize, weight: k == 0 ? .semibold : .medium))
                            .foregroundStyle(k == 0 ? nowTone : WidgetTone.muted)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: tw)
                    }
                }
                .frame(height: headerHeight, alignment: .top)
                // The rule under the header, inside its height so the row geometry is unchanged.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(rule).frame(height: 0.5)
                }

                ForEach(Array(cities.enumerated()), id: \.offset) { _, city in
                    let zone = TimeZone(identifier: city.timeZoneID) ?? .current
                    HStack(spacing: 0) {
                        // Shorter rows than designed for: a smaller time, then no caption.
                        ViewThatFits(in: .vertical) {
                            stripLabel(city, zone: zone, timeSize: timeSize, nameSize: nameSize,
                                       captionSize: captionSize, captioned: true)
                            stripLabel(city, zone: zone, timeSize: max(15, timeSize * 0.8), nameSize: nameSize,
                                       captionSize: captionSize, captioned: true)
                            stripLabel(city, zone: zone, timeSize: max(15, timeSize * 0.8), nameSize: nameSize,
                                       captionSize: captionSize, captioned: false)
                        }
                        .frame(width: textWidth, height: rowHeight, alignment: .leading)

                        Color.clear.frame(width: clear, height: 1)

                        HStack(spacing: spacing) {
                            ForEach(-half...half, id: \.self) { k in
                                let start = anchor.addingTimeInterval(Double(k) * 3600)
                                let stacked = !snapshot.use24h && th >= 30
                                tile(start, zone: zone, stacked: stacked)
                                    .frame(width: tw, height: th)
                                    .scaleEffect(k == 0 ? Self.nowScale : 1)
                                    .overlay(alignment: .top) {
                                        // A new day: its weekday tag, inside the tile's top edge (the Now
                                        // tile's: 2 pt inside the larger tile, under the outline's top
                                        // line), or across the edge where the digits are close, never
                                        // past the row's card (which starts 6 pt or more above the tile).
                                        if macStartsNewDay(start, zone: zone) {
                                            let edge: CGFloat = k == 0 ? -th * grow : 0
                                            let tag = Self.macTuckedTag(tile: th, stacked: stacked, now: k == 0,
                                                                        top: edge + 2, limit: k == 0 ? edge + 1 : -5)
                                            macDayTag(start, zone: zone, height: tag.height).offset(y: tag.y)
                                        }
                                    }
                                    .frame(width: tw, height: rowHeight)
                            }
                        }
                    }
                    .frame(height: rowHeight)
                    .background {
                        if photos {
                            MacWidgetRowPhoto(city: city, date: date, focusX: focus)
                                .overlay(scrim)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.horizontal, -6)
                        }
                    }
                }
            }
            // The Now outline, through every row: concentric with the Now tiles.
            .overlay(alignment: .topLeading) {
                nowOutline(width: outlineWidth, height: outlineHeight, radius: 6 * Self.nowScale + inset,
                           tintedTone: Color.primary.opacity(0.6))
                    .offset(x: outlineX, y: outlineY)
            }
        }
    }

    /// A row's time, name and caption. On its photo the time and name carry a soft dark halo and
    /// the caption (small text) sits on a dark chip; the chip is never truncated.
    private func stripLabel(_ city: WidgetSnapshot.City, zone: TimeZone, timeSize: CGFloat, nameSize: CGFloat,
                            captionSize: CGFloat, captioned: Bool) -> some View {
        let (clock, suffix) = Self.clock(date, zone: zone, use24h: snapshot.use24h)
        return VStack(alignment: .leading, spacing: 0) {
            WidgetClockText.text(clock, suffix: suffix, size: timeSize)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .macHalo(photos)
            Text(city.name)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(WidgetTone.primary)
                .lineLimit(1)
                .minimumScaleFactor(Self.largeNameMinScale)
                .macHalo(photos)
            if captioned {
                Text(caption(zone, short: true))
                    .font(.system(size: captionSize, weight: photos ? .semibold : .medium))
                    .foregroundStyle(photos ? WidgetTone.primary : WidgetTone.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, photos ? 6 : 0)
                    .padding(.vertical, photos ? 1 : 0)
                    .background { if photos { Capsule().fill(Self.chipTone) } }
            }
        }
    }
    #endif

    /// `stacked` (tiles tall enough): AM/PM under the hour. The new day's weekday tag is drawn by the
    /// callers, above or inside the tile's top edge.
    private func tile(_ moment: Date, zone: TimeZone, stacked: Bool = false) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: moment)
        let minute = calendar.component(.minute, from: moment)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60, lifted: true)
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
    }

    /// The tile's hour. Only the digits may shrink; AM/PM stays 12 pt (Mac: 11 pt), after the hour or,
    /// when `stacked`, under it, with the label clear of the tile's rounded corners.
    @ViewBuilder
    private func tileLabel(hour: Int, minute: Int, stacked: Bool) -> some View {
        let suffix: String? = snapshot.use24h ? nil : (hour < 12 ? "AM" : "PM")
        if stacked, let suffix {
            VStack(spacing: -1) {
                if minute != 0 {
                    // "8:30": ":30" steps down to 11 pt first, then the hour 15 -> 14 -> 13 pt; the old
                    // all-together 0.8 shrink is the last fallback. ViewThatFits picks by ideal
                    // (unscaled) size, so each step is a fixed size, not a minimumScaleFactor.
                    ViewThatFits(in: .horizontal) {
                        halfHourDigits(hour, minute, hourSize: Self.tileSize + 2, minuteSize: Self.tileMinuteSize)
                        halfHourDigits(hour, minute, hourSize: Self.tileSize + 2, minuteSize: 11)
                        halfHourDigits(hour, minute, hourSize: Self.tileSize + 1, minuteSize: 11)
                        halfHourDigits(hour, minute, hourSize: Self.tileSize, minuteSize: 11)
                        tileDigits(hour: hour, minute: minute)
                            .font(.system(size: Self.tileSize + 2, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    tileDigits(hour: hour, minute: minute)
                        .font(.system(size: Self.tileSize + 2, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(Self.tileScale(minute: minute, use24h: snapshot.use24h))
                }
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
    }

    /// "9" or "09", with ":30" smaller in half-hour zones.
    private func tileDigits(hour: Int, minute: Int) -> Text {
        var text = snapshot.use24h ? Text(String(format: "%02d", hour)) : Text("\(hour % 12 == 0 ? 12 : hour % 12)")
        if minute != 0 {
            text = text + Text(":\(String(format: "%02d", minute))")
                .font(.system(size: Self.tileMinuteSize, weight: .medium))
        }
        return text
    }

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

/// Where a photo sits in a widget row (both platforms): scaled just enough to cover the frame
/// (aspect-fill), and up to 15% more only so its horizontal centre can slide toward `focusX` (the
/// clear gap's centre; nil: centred), never further; the point `focus` (0…1) of the way down the
/// photo (its skyline band) at the frame's vertical centre. Both offsets are clamped so the photo
/// still covers the frame. Returns the photo's size and its top-left offset in the frame.
enum WidgetPhotoPlacement {
    /// The skyline's usual height in a photo with no measured focus (downloaded photos, old indexes).
    static let defaultFocus: CGFloat = 0.62

    static func place(imageWidth: CGFloat, imageHeight: CGFloat, in frame: CGSize, focus: CGFloat,
                      focusX: CGFloat?) -> (size: CGSize, offset: CGPoint) {
        let fw = max(frame.width, 1), fh = max(frame.height, 1)
        let iw = max(imageWidth, 1), ih = max(imageHeight, 1)
        let cover: CGFloat = max(fw / iw, fh / ih)
        var scale: CGFloat = cover
        var centreX: CGFloat = fw / 2
        if let focusX {
            let target = min(max(focusX, 0), fw)
            let needed: CGFloat = 2 * max(target, fw - target) / iw
            scale = min(max(cover, needed), cover * 1.15)
            centreX = target
        }
        let w = iw * scale, h = ih * scale
        let x = min(max(centreX - w / 2, fw - w), 0)
        let f = min(max(focus, 0), 1)
        let y = min(max(fh / 2 - f * h, fh - h), 0)
        return (CGSize(width: w, height: h), CGPoint(x: x, y: y))
    }
}

#if !os(iOS)
/// Mac: a widget row's photo (the widget's own 600 px copies; the night photo after dark, or the
/// day photo darkened when the city has none), sharp, placed by WidgetPhotoPlacement: its skyline
/// band (MacSkylines.focus) at the row's vertical centre, its centre slid toward `focusX` (points
/// from the frame's left edge) by at most 15% extra zoom. A city with no photo keeps its sky.
private struct MacWidgetRowPhoto: View {
    let city: WidgetSnapshot.City
    let date: Date
    let focusX: CGFloat

    var body: some View {
        let night = MacSkylines.wantsNight(timeZoneID: city.timeZoneID, latitude: city.latitude,
                                           longitude: city.longitude, at: date)
        let nightPhoto: CGImage? = night
            ? MacSkylines.image(name: city.name, timeZoneID: city.timeZoneID, night: true, maxPixel: 600) : nil
        let photo: CGImage? = nightPhoto
            ?? MacSkylines.image(name: city.name, timeZoneID: city.timeZoneID, night: false, maxPixel: 600)
        let dimmed = night && nightPhoto == nil
        let focus: CGFloat = MacSkylines.focus(name: city.name, timeZoneID: city.timeZoneID, night: nightPhoto != nil)
        ZStack {
            if let photo {
                GeometryReader { geo in
                    let fit = WidgetPhotoPlacement.place(imageWidth: CGFloat(photo.width),
                                                         imageHeight: CGFloat(photo.height),
                                                         in: geo.size, focus: focus, focusX: focusX)
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.size.width, height: fit.size.height)
                        .offset(x: fit.offset.x, y: fit.offset.y)
                }
                .overlay { if dimmed { Color.black.opacity(0.45) } }
            } else {
                MacSkylineBackdrop(name: city.name, timeZoneID: city.timeZoneID, latitude: city.latitude,
                                   longitude: city.longitude, date: date, maxPixel: 600, synchronous: true)
            }
        }
        .clipped()
    }
}

private extension View {
    /// Mac widgets: the soft dark halo that keeps the time and the city name readable on a photo
    /// that is hardly darkened (none in the tinted modes, which draw no photo).
    func macHalo(_ on: Bool) -> some View {
        self.shadow(color: Color.black.opacity(on ? 0.75 : 0), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(on ? 0.55 : 0), radius: 5, x: 0, y: 0)
            .shadow(color: Color.black.opacity(on ? 0.35 : 0), radius: 11, x: 0, y: 0)
    }
}
#endif

#if os(iOS)
/// Lock Screen widgets: inline (above the clock), circular and rectangular. They follow the
/// Lock Screen's own tint, so they use plain text and shapes rather than the brand colours.
struct AccessoryClockView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The rectangular widget's text grows 10% above the default text size (capped at xLarge).
    private var typeScale: CGFloat { WidgetType.scale(typeSize) }

    private func zone(_ city: WidgetSnapshot.City) -> TimeZone { TimeZone(identifier: city.timeZoneID) ?? .current }
    /// "SF" for San Francisco, "NY" for New York, "LON" for London.
    private func tag(_ city: WidgetSnapshot.City) -> String {
        let words = city.name.split(whereSeparator: { !$0.isLetter }).filter { !$0.isEmpty }
        if words.count > 1 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
        return String(city.name.filter(\.isLetter).prefix(3)).uppercased()
    }
    /// "12:41\u{2009}PM" (the thin space the rectangular widget and the app's tiles use; U+202F
    /// rendered about 2 px wide here, so the line read "12:41PM") or "14:05".
    private func inlineTime(_ city: WidgetSnapshot.City) -> String {
        let (clock, suffix) = WidgetClockView.clock(date, zone: zone(city), use24h: snapshot.use24h)
        return suffix.map { clock + "\u{2009}" + $0 } ?? clock
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
            // with a thin space before AM/PM, as everywhere else. Falls back to the first
            // city alone where both don't fit (the gap is never closed, and "LON 5:41…" never shows).
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
                        .font(.system(size: 12 * typeScale, weight: .semibold))
                        .lineLimit(1)
                    Text(clock)
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .widgetAccentable()
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    if let suffix {
                        Text(suffix)
                            .font(.system(size: 12 * typeScale, weight: .semibold))
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
                            .font(.system(size: 13 * typeScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 2)
                        // Another day stays visible ("+1 d"), as before.
                        (WidgetClockText.text(clock, suffix: suffix, size: 15 * typeScale)
                            + Text(shift(city)).font(.system(size: 11 * typeScale, weight: .medium)))
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
    /// photo's file when it has one (nil: the day photo is darkened at night, as before), and how
    /// far down the photo its skyline band sits (0…1, from skylines.json; nil: unknown).
    struct Entry: Codable, Equatable {
        var file: String
        var source: String
        var night: String? = nil
        var focus: Double? = nil
    }

    /// A photo the widget shows: the image, whether it is a real night photo (shown as taken) and
    /// a key naming the file it came from (for the brightness cache).
    struct Photo {
        let image: CGImage
        let isNight: Bool
        let key: String
        /// How far down the photo its skyline band sits (WidgetPhotoPlacement centres it in the row).
        var focus: CGFloat = WidgetPhotoPlacement.defaultFocus
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
    /// Screenshot mode: the in-app photo's skyline focus (day or night), nil when unknown.
    static var inAppFocus: ((WidgetSnapshot.City, Bool) -> Double?)?

    private static func focus(_ value: Double?) -> CGFloat {
        value.map { CGFloat(min(max($0, 0), 1)) } ?? WidgetPhotoPlacement.defaultFocus
    }

    /// The photo the city shows at `date`: by day its day photo (which WidgetSky.look then tints for
    /// the time of day); after dark (once the sun has set there, until the hour before sunrise) its
    /// night photo, or nil (the drawn night sky) when it has none; a day photo is never darkened to
    /// stand in for night. Nil: the widget draws its sky. Matches the app's Skyline.photo(for:at:).
    static func photo(for city: WidgetSnapshot.City, at date: Date) -> Photo? {
        if WidgetSky.wantsNightPhoto(city, at: date) { return image(for: city, night: true) }
        return image(for: city, night: false)
    }

    /// The city's day or night photo, downsampled to at most 600 px, or nil.
    static func image(for city: WidgetSnapshot.City, night: Bool) -> Photo? {
        if let provide = night ? inAppNightImage : inAppImage {
            let f = focus(inAppFocus?(city, night))
            return provide(city).map { Photo(image: $0, isNight: night, key: "app|\(city.id)|\(night)", focus: f) }
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
        let photoFocus = focus(night ? entries[city.id + "|night"]?.focus : entry.focus)
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
        if let hit = images[key] { return Photo(image: hit, isNight: night, key: key, focus: photoFocus) }
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
        return Photo(image: image, isNight: night, key: key, focus: photoFocus)
    }

    /// What the scrim behind a card's text has to do: `boost`, a flat layer of extra black over the
    /// name, status and time (bottom-left, feathered 12 pt above and wide to the right, as Android's
    /// clear()) so the white name and status keep about 7.5:1 (p95 at most WidgetScrim.labelMax) and the time 5:1 against the brightest twentieth (p95), sampled
    /// 6 pt past the glyphs, of the photo behind it, and `bright`, whether the area behind the time is still too bright for white and bright on
    /// average (the time then switches to dark ink, as the app's, and the boost covers the name only).
    struct Backing: Equatable {
        var boost = WidgetScrim.Boost()
        var bright = false
    }

    /// The feather above the boost, in points.
    static let boostFeather: CGFloat = 12
    /// The feather to the right of the boost, as a fraction of the card's longer side (Android's
    /// clear() uses 0.20 with a linear ramp; this eased ramp is steeper in its middle, so 0.30). It
    /// was 12 pt, which ended the boost in a visible seam on a bright day sky (NY: 96 to 171 in
    /// 8 pt); over about 100 pt on a medium row the steepest 8 pt changes by at most about 10 levels.
    static let boostFeatherAcross: Double = 0.30

    /// `textRegion` and `timeRegion` are areas of a card of `size` in its unit square (top-left
    /// origin): where the name and status sit, and where the time does. The boost covers both.
    static func backing(_ photo: Photo?, phase: WidgetSky.Phase, size: CGSize,
                        textRegion: CGRect, timeRegion: CGRect) -> Backing {
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        let aspect = CGFloat(w / h)
        // The boost's shape: full over `region` and everything below and left of it, feathered
        // 12 pt above and 30% of the card's longer side to the right.
        func shaped(_ region: CGRect, amount: Double) -> WidgetScrim.Boost {
            let top = min(max(Double(region.minY), 0), 1)
            let right = min(max(Double(region.maxX), 0), 1)
            return WidgetScrim.Boost(amount: amount, top: top, right: right,
                                     featherV: min(Double(boostFeather) / h, top),
                                     featherH: min(boostFeatherAcross * max(w, h) / w, 1 - right))
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
        // The smallest boost (in 0.05 steps, up to 0.55) that brings the brightest twentieth behind
        // the name and status under `labelMax` (0.09, as the app's name column and Android's LABEL_MAX:
        // white text about 7.5:1; was 0.16, 5:1, and the worst pixels behind "San Francisco" measured
        // 5.2 to 5.5:1); a dark night photo needs none. Sized for the name, not the time, so a day
        // photo still looks like day.
        for step in WidgetScrim.boostSteps {
            boost.amount = step
            let text = photoLuminance(photo, phase: phase, aspect: aspect, region: textRegion, boost: boost)?.p95 ?? 0
            if text <= WidgetScrim.labelMax { break }
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
        // Twilight on a photo: warm, but hardly darker (was #F0D1B6, about a sixth of its light gone;
        // #FFF2E0 takes about 5%), so the photo stays the picture.
        if phase == .twilight { return (shade: (1, 0.949, 0.878), saturation: saturation(phase)) }
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
        case .offHours: hex = 0xD9DEE6           // the app's WorkStatus ink (was #B9C3CF, 0.54 luminance vs the app's 0.73)
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

/// No longer drawn over the photo widgets (WidgetTextShade is); kept for WidgetSkylines.backing.
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
    /// In 0.05 steps (were 0.15), as Android's, so a photo is darkened no more than its text needs.
    static let boostSteps: [Double] = [0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55]
    /// For white digits on a partly lit area: further (to 0.65), covering the name and time.
    static let timeBoostSteps: [Double] = boostSteps + [0.6, 0.65]
    /// The brightest the brightest twentieth behind the name and status may be (relative luminance):
    /// 0.09, the app's and Android's LABEL_MAX (white about 7.5:1).
    static let labelMax = 0.09

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

/// The only darkening left on a photo: black at 45% along the left edge, eased (smoothstep, nine
/// stops, so no edge or band shows) to nothing at `end` (a fraction of the width: where the name
/// and time end). Right of that the photo is as taken.
struct WidgetTextShade: View {
    static let opacity = 0.45
    var end: CGFloat = 0.7

    var body: some View {
        let reach = min(max(end, 0.05), 1)
        let stops: [Gradient.Stop] = (0...8).map { i -> Gradient.Stop in
            let t = Double(i) / 8
            let eased = t * t * (3 - 2 * t)
            return Gradient.Stop(color: Color.black.opacity(Self.opacity * (1 - eased)), location: reach * CGFloat(t))
        }
        LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

private extension View {
    /// The soft dark halo that carries the time and the city name on a photo that is hardly darkened.
    func widgetPhotoHalo() -> some View {
        self.shadow(color: Color.black.opacity(0.75), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.35), radius: 22, x: 0, y: 0)
    }
}

/// A city's photo, sharp across the whole space, or its sky when there's no photo. Placed by
/// WidgetPhotoPlacement: its skyline band (`photo.focus`) at the frame's vertical centre, scaled to
/// cover, and slid toward `focusX` (points from the left: the middle of the clear gap between a
/// row's text and its tiles; nil: centred) by at most 15% extra zoom.
/// The only darkening is WidgetTextShade over the text on the left. A night photo shows as taken;
/// a day photo as taken by day, lightly warmed in twilight. Crossfades when the photo changes.
struct WidgetCityBackdrop: View {
    let city: WidgetSnapshot.City
    let date: Date
    let photo: WidgetSkylines.Photo?
    var focusX: CGFloat? = nil
    /// Where the left shade ends, as a fraction of the width.
    var shadeEnd: CGFloat = 0.7

    var body: some View {
        let phase = WidgetSky.phase(city, at: date)
        ZStack {
            if let photo {
                let look = WidgetSky.look(phase, nightPhoto: photo.isNight)
                GeometryReader { geo in
                    let fit = WidgetPhotoPlacement.place(imageWidth: CGFloat(photo.image.width),
                                                         imageHeight: CGFloat(photo.image.height),
                                                         in: geo.size, focus: photo.focus, focusX: focusX)
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .saturation(look.saturation)
                        .colorMultiply(Color(red: look.shade.0, green: look.shade.1, blue: look.shade.2))
                        .frame(width: fit.size.width, height: fit.size.height)
                        .offset(x: fit.offset.x, y: fit.offset.y)
                }
                .clipped()
                .id(photo.key)
                .transition(.opacity)
            } else {
                LinearGradient(colors: WidgetSky.sky(phase), startPoint: .top, endPoint: .bottom)
            }
            WidgetTextShade(end: shadeEnd)
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
        // White digits (every photo face now): the dark halo, as the name's (widgetPhotoHalo).
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.4 : 0.75), radius: bright ? 3 : 2, x: 0, y: bright ? 0 : 1)
        .shadow(color: Color.black.opacity(bright ? 0 : 0.55), radius: 10, x: 0, y: 0)
        .shadow(color: Color.black.opacity(bright ? 0 : 0.35), radius: 22, x: 0, y: 0)
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

/// The app's status pill, small: an icon and the status in its colour (the app's inks) on a dark
/// backing: 12 pt with an 11 pt icon, as the app's (was 11 pt), on black at 75% (was 65%), so even
/// over pure white every status keeps 4.8:1 or more ("Off hours" 7.7:1), whatever the photo.
struct WidgetStatusPill: View {
    let status: WidgetWorkStatus
    var size: CGFloat = 12

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scaled = size * WidgetType.scale(typeSize)
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.system(size: scaled * 11 / 12, weight: .semibold))
            Text(status.title)
                .font(.system(size: scaled, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .overlay(Capsule().strokeBorder(status.color.opacity(0.5), lineWidth: 1))
    }
}

/// The city name on a photo, with a soft shadow; grows with the reader's text size (to xLarge).
private struct WidgetCityName: View {
    let name: String
    let size: CGFloat

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(name)
            .font(.system(size: size * WidgetType.scale(typeSize), weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.9)   // 13 pt never under 11.7 pt (was 0.85)
            .widgetPhotoHalo()
    }
}

private func widgetCityName(_ name: String, size: CGFloat) -> some View {
    WidgetCityName(name: name, size: size)
}

/// Medium and large: each city a row filled with its skyline photo (rounded, small gaps), the time,
/// name and status bottom-left and the hour before, the hour now and the hour after bottom-right;
/// one Now capsule runs down the middle tiles of every row, as in the app.
struct WidgetPhotoRows: View {
    let snapshot: WidgetSnapshot
    let cities: [WidgetSnapshot.City]
    let date: Date
    /// The most cities this widget shows (large 5, medium 2): with that many the rows are their
    /// normal size; with fewer they share the height and their contents grow (body).
    var maxCities = 5

    static let gap: CGFloat = 5
    static let radius: CGFloat = 12
    static let sidePadding: CGFloat = 9
    static let bottomPadding: CGFloat = 7
    static let tileGap: CGFloat = 4
    /// The space either side of the Now tile: the tile gap and 3 pt more (with three tiles, both
    /// gaps), so the outline's line has clear room.
    static let nowGap: CGFloat = tileGap + 3
    /// The clear gap kept between the text and the first tile wherever the text leaves the room.
    static let clearGap: CGFloat = 40
    /// The Now outline's centre line runs this far outside the Now tiles: half the gap (3.5 pt), so
    /// it sits exactly midway between the Now tiles and their neighbours (and as far above and below).
    static let inset: CGFloat = nowGap / 2
    /// The outline's white core and the dark edge each side of it: 1.5 + 2 x 0.75 = 3 pt, so
    /// 3.5 - 1.5 = 2 pt stays clear to the Now tile and to its neighbour.
    static let core: CGFloat = 1.5
    static let edge: CGFloat = 0.75
    static let band: CGFloat = core + 2 * edge
    /// The Now tile grows this much above and below the others (up to 4 pt), as far as the card's
    /// bottom padding allows with the outline's band still on the last card: 7 - 3.5 - 1.5 = 2.
    static let nowRise: CGFloat = min(4, max(2, bottomPadding - inset - band / 2))

    /// About how wide `text` sets in the system's semibold (the time's digits monospaced), to size
    /// a row's text block before it is laid out.
    private static func measure(_ text: String, size: CGFloat, digits: Bool = false) -> CGFloat {
        let font = digits ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            : UIFont.systemFont(ofSize: size, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The Now tile about 12% wider than the other two (40 -> 45 pt); they keep their width.
    static func nowWidth(_ tileWidth: CGFloat) -> CGFloat { (tileWidth * 1.12).rounded() }

    /// The new day's weekday tag (WidgetPhotoDayTag): its height, and its top from its tile's top.
    /// `space` is the card's top to the tile's top. Above the tile with 3 pt between them (15 pt high,
    /// or 13 where the card is short), always 1 pt or more inside the card. Where even that does not
    /// fit (the taller Now tile) it sits as high as the card lets it, over the tile's top edge only.
    /// `outline`: the Now outline's top line passes over this tile (the first row's Now tile): 2 pt
    /// clear above its band, else 2 pt inside the tile.
    static func dayTag(space: CGFloat, outline: Bool) -> (height: CGFloat, y: CGFloat) {
        let clear: CGFloat = outline ? inset + band / 2 + 2 : 3
        for h in [CGFloat(15), CGFloat(13)] where space >= h + clear + 1 {
            return (height: h, y: -(h + clear))
        }
        if outline { return (height: 13, y: 2) }
        return (height: 13, y: -max(0, min(space - 1, 13 + clear)))
    }

    /// How far a tile's label moves down so a tag reaching `tagBottom` into the tile stays clear of
    /// its digits (about 4 pt of a label's first line is above the digits): nothing unless the tag
    /// is inside the tile, and never more than the tile has spare.
    static func labelDrop(tagBottom: CGFloat, tileHeight: CGFloat, labelHeight: CGFloat) -> CGFloat {
        let spare = max(0, tileHeight - labelHeight)
        return max(0, min(spare, 2 * (tagBottom - 3) - spare))
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geo in
            let n = max(cities.count, 1)
            let rowHeight = max(30, ((geo.size.height - Self.gap * CGFloat(n - 1)) / CGFloat(n)).rounded(.down))
            // The rows share the widget's height, however many there are. With the most cities this
            // widget shows they are `baseHeight` and everything is its normal size (scale 1); with
            // fewer the rows are taller and their contents grow with them, each to its cap: the time
            // to 1.5x, the name and status to 1.25x (row), the tiles to 1.4x as tall and 1.1x as wide.
            let most = max(maxCities, n)
            let baseHeight = max(30, ((geo.size.height - Self.gap * CGFloat(most - 1)) / CGFloat(most)).rounded(.down))
            let scale = max(1, rowHeight / baseHeight)
            let tileHeight = (min(44, max(22, baseHeight - 24)) * min(1.4, scale)).rounded()
            let baseTileWidth = min(40, ((geo.size.width * 0.42 - 2 * Self.tileGap) / 3).rounded(.down))
            let tileWidth = (baseTileWidth * min(1.1, scale)).rounded()
            let clockSize = (min(34, max(17, (baseHeight * 0.28).rounded())) * min(1.5, scale)).rounded()
            VStack(spacing: Self.gap) {
                ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                    row(city, width: geo.size.width, height: rowHeight, tileWidth: tileWidth, tileHeight: tileHeight,
                        clockSize: clockSize, scale: scale, first: index == 0)
                }
            }
            .frame(width: geo.size.width, alignment: .top)
            .overlay(alignment: .topLeading) {
                capsule(width: geo.size.width, rows: cities.count, rowHeight: rowHeight,
                        tileWidth: tileWidth, tileHeight: tileHeight)
            }
        }
    }

    /// One outline through the Now tile of every row: a rounded rectangle concentric with the Now
    /// tiles, its centre line `inset` (half the 7 pt gap) outside them on every side, its corners the
    /// tiles' radius + inset. An outline only (a white wash lightened the tile under it); the dark
    /// edge either side of the white core keeps it at 3:1 or more on bright or dark photos, and the
    /// whole band stays inside the gap, 2 pt clear of both tiles. Its bottom edge ends on the
    /// last card's bottom edge (7 - 2 - 3.5 - 1.5 = 0), never on the bare widget background.
    private func capsule(width: CGFloat, rows: Int, rowHeight: CGFloat, tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let nowWidth = Self.nowWidth(tileWidth)
        let nowLeft = width - Self.sidePadding - tileWidth - Self.nowGap - nowWidth
        let n = CGFloat(max(rows, 1))
        let firstTop = rowHeight - Self.bottomPadding - tileHeight - Self.nowRise
        let lastBottom = n * rowHeight + (n - 1) * Self.gap - Self.bottomPadding + Self.nowRise
        let top = firstTop - Self.inset
        let bottom = lastBottom + Self.inset
        // .stroke (centred on the path, not .strokeBorder, which insets), so the line's centre is
        // exactly the rect below.
        let shape = RoundedRectangle(cornerRadius: WidgetPhotoTile.radius + Self.inset, style: .continuous)
        return ZStack {
            shape.stroke(Color.black.opacity(0.6), lineWidth: Self.band)
            shape.stroke(Color.white.opacity(0.85), lineWidth: Self.core)
        }
            .frame(width: nowWidth + 2 * Self.inset, height: max(1, bottom - top))
            .offset(x: nowLeft - Self.inset, y: top)
    }

    private func row(_ city: WidgetSnapshot.City, width: CGFloat, height: CGFloat,
                     tileWidth: CGFloat, tileHeight: CGFloat, clockSize: CGFloat, scale: CGFloat, first: Bool) -> some View {
        let zone = TimeZone(identifier: city.timeZoneID) ?? .current
        let photo = WidgetSkylines.photo(for: city, at: date)
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        // The row: [time, name, status] [clear gap] [tiles]. The text may take what the tiles leave
        // less the 40 pt clear gap (never under 104 pt while the row has it); the block's own width
        // is measured, so the photo's centre can sit in the middle of what is really clear.
        let type = WidgetType.scale(typeSize)
        let tilesWidth = 2 * tileWidth + Self.nowWidth(tileWidth) + 2 * Self.nowGap
        let inner = width - 2 * Self.sidePadding
        let textMax = max(40, inner - tilesWidth - Self.clearGap, min(104, inner - tilesWidth - 6))
        let clock = WidgetClockView.clock(date, zone: zone, use24h: snapshot.use24h)
        let suffixWidth: CGFloat = clock.1.map { Self.measure("\u{2009}" + $0, size: max(13, clockSize * 0.45)) } ?? 0
        let timeWidth = Self.measure(clock.0, size: clockSize, digits: true) + suffixWidth + clockSize / 6
        let nameWidth = Self.measure(city.name, size: 13 * type)
        // The pill: its 11 pt icon (about 14 pt wide), 3 pt, the title, 6 pt each side and its edge.
        let pillWidth: CGFloat = status.map { Self.measure($0.title, size: 12 * type) + 14 * type + 17 } ?? 0
        // The name and status grow with a taller row (to 1.25x), but never so far that the 40 pt
        // clear gap closes (one city on a medium: 1.17x, not 1.25x, which left 33 pt).
        let labelRoom = max(0, inner - tilesWidth - Self.clearGap)
        let labelScale = min(1.25, scale, max(1, min(textMax, labelRoom) / max(nameWidth, pillWidth, 1)))
        let block = min(textMax, max(timeWidth, nameWidth * labelScale, pillWidth * labelScale).rounded(.up))
        // The middle of the clear gap, from the row's left edge: where the photo's centre goes.
        let focus = Self.sidePadding + block + (inner - tilesWidth - block) / 2
        let anchor = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        // AM/PM goes under the hour whenever the tile is tall enough (inline "11 AM" filled a 40 pt
        // tile edge to edge), and always on narrow tiles and in half-hour zones ("9:30" over "AM"),
        // so every row, Mumbai's included, reads the same two-line way.
        let halfHour = zone.secondsFromGMT(for: date) % 3600 != 0
        let stacked = !snapshot.use24h && (tileHeight >= 31 || tileWidth < 39 || halfHour)
        // The digits grow a little with a taller row's tiles (to 1.125x: 16 -> 18 pt, Now 18 -> 20).
        let digitSize: CGFloat = ((stacked && tileHeight >= 34 ? 16 : 14) * min(1.125, scale)).rounded()
        // The row's widest hour ("10" of "8:30", "9:30", "10:30"), so its three tiles share one
        // digit size (the "10" in "10:30" shrank alone, smaller than the "8" and "9" beside it).
        let widest: String = (-1...1).map { k -> String in
            var there = Calendar(identifier: .gregorian)
            there.timeZone = zone
            let h = there.component(.hour, from: anchor.addingTimeInterval(Double(k) * 3600))
            return WidgetPhotoTile.digits(h, use24h: snapshot.use24h)
        }.max { $0.count < $1.count } ?? ""
        return ZStack(alignment: .bottomLeading) {
            WidgetCityBackdrop(city: city, date: date, photo: photo, focusX: focus,
                               shadeEnd: (Self.sidePadding + block) / max(width, 1))
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: clockSize)
                        .widgetAccentable()
                        .layoutPriority(1)
                    ViewThatFits(in: .vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            widgetCityName(city.name, size: 13 * labelScale)
                            if let status { WidgetStatusPill(status: status, size: 12 * labelScale) }
                        }
                        widgetCityName(city.name, size: 13 * labelScale)
                    }
                }
                .frame(maxWidth: textMax, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                HStack(spacing: Self.nowGap) {
                    ForEach(-1...1, id: \.self) { k in
                        // The Now tile: wider, `nowRise` taller above and below the others' centre
                        // line (the negative padding keeps the others where they were), digits +2 pt.
                        // Where a new day starts in the tile, its weekday tag goes above it (dayTag).
                        let ownHeight: CGFloat = k == 0 ? tileHeight + 2 * Self.nowRise : tileHeight
                        let ownDigits: CGFloat = k == 0 ? digitSize + 2 : digitSize
                        let tag = Self.dayTag(space: height - Self.bottomPadding - tileHeight - (k == 0 ? Self.nowRise : 0),
                                              outline: first && k == 0)
                        let minorLine: CGFloat = (k == 0 ? 13 : 12) * WidgetType.scale(typeSize) * 1.2
                        let labelHeight: CGFloat = stacked ? ownDigits * 1.2 + minorLine - 1 : 20
                        WidgetPhotoTile(snapshot: snapshot, city: city, zone: zone,
                                        start: anchor.addingTimeInterval(Double(k) * 3600), center: k == 0,
                                        stacked: stacked, digitSize: ownDigits, widest: widest,
                                        tagHeight: tag.height, tagY: tag.y,
                                        labelDrop: Self.labelDrop(tagBottom: tag.y + tag.height, tileHeight: ownHeight,
                                                                  labelHeight: labelHeight))
                            .frame(width: k == 0 ? Self.nowWidth(tileWidth) : tileWidth,
                                   height: ownHeight)
                            .padding(.vertical, k == 0 ? -Self.nowRise : 0)
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
/// "9:30" zones; as the app's), after it ("9 AM") only on short tiles. Midnight and noon read as every
/// other hour ("12", "AM" and "12", "PM"; "00" in 24-hour time); where a new day starts, its weekday
/// is a small gold tag above the tile (WidgetPhotoDayTag), as the app's.
struct WidgetPhotoTile: View {
    let snapshot: WidgetSnapshot
    let city: WidgetSnapshot.City
    let zone: TimeZone
    let start: Date
    let center: Bool
    var stacked = false
    var digitSize: CGFloat = 14
    /// The widest hour in the row ("10"), measured by every tile so the row shares one digit size.
    var widest: String = ""
    /// The new day's weekday tag: its height, its top from the tile's top (negative: above), and how
    /// far the label moves down to stay clear of a tag inside the tile (WidgetPhotoRows.dayTag).
    var tagHeight: CGFloat = 15
    var tagY: CGFloat = -18
    var labelDrop: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var typeSize
    /// AM/PM and ":30" grow with the reader's text size, as the rows' names and captions (12 -> 13.2 pt).
    private var typeScale: CGFloat { WidgetType.scale(typeSize) }
    /// The tiles' corner radius (the Now outline's corners are this + its inset, concentric).
    static let radius: CGFloat = 6
    /// AM/PM and ":30": 12 pt, 13 on the larger Now tile.
    private var minorPoints: CGFloat { center ? 13 : 12 }

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        let newDay = !calendar.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
        let dim = WidgetWorkStatus.dims(city, snapshot: snapshot, hourStart: start)
        // Working tiles are floored at 0.12 luminance only while working hours are highlighted
        // (off tiles then sit beside them); otherwise the plain sky, night tiles stay night.
        let highlights = snapshot.showStatus ?? true
        let fill = dim ? DayColor.offHoursFill(at: Double(hour) + Double(minute) / 60)
            : (highlights ? DayColor.workingFill(at: Double(hour) + Double(minute) / 60) : style.fill)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let suffix: String? = snapshot.use24h ? nil : (hour < 12 ? "AM" : "PM")
        return Group {
            if stacked && minute != 0 {
                halfHourLabel(hour: hour, minute: minute, suffix: suffix)
            } else if stacked {
                // The hour over AM/PM, as the app's tiles: only the digits may shrink, one size for
                // the whole row (sharedLabel); AM/PM stays 12 pt.
                VStack(spacing: -1) {
                    sharedLabel(hour: hour, minute: minute)
                    if let suffix {
                        Text(suffix)
                            .font(suffixFont)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                    }
                }
            } else {
                // Inline ("9 AM"): 24-hour labels, and the fallback for tiles under 31 pt tall,
                // where shrinking the whole label (to 0.85) beats truncating it.
                (suffix.map { label(Self.digits(hour, use24h: snapshot.use24h), minute: minute) + Text("\u{2009}" + $0).font(suffixFont) }
                    ?? label(Self.digits(hour, use24h: snapshot.use24h), minute: minute))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .foregroundStyle(style.text)
        // Clear of the tile's rounded corners: 6 pt each side (was 1) on full-hour stacked tiles; half-hour tiles take none (below), and ":30 PM" at 12 pt still does not fit a 40 pt tile, so it falls to the ladder.
        // Half-hour tiles: no side padding (was 2): "10:30" at the row's 16 pt (about 37.6 pt) did not
        // fit 36 pt, so the hour fell down the ladder to about 12 pt, 24% under the other rows'; at 40 pt
        // it fits, and the text still sits on the tile's straight middle, clear of the 6 pt corners.
        .padding(.horizontal, stacked ? (minute != 0 ? 0 : 6) : 3)
        .padding(.top, newDay ? labelDrop : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Off-hours tiles are darkened, never see-through (was 88% opacity: the photo showed
        // through behind the numerals), as the app's.
        .background(shape.fill(fill))
        // Night and off-hours tiles are near-black: a 1 pt edge at 32% white (was 0.5 pt at 16%,
        // 1.3:1) keeps the row reading as tiles on a dark night photo, as the app's HourTiles.
        .overlay(shape.strokeBorder(Color.white.opacity(dim || hour < 6 || hour >= 21 ? 0.32 : 0), lineWidth: 1))
        .overlay(alignment: .top) {
            // A new day: its weekday in a small gold tag centred above the tile, never wider than it.
            if newDay {
                WidgetPhotoDayTag(weekday: Self.weekday(start, zone: zone, format: "EEE").uppercased(),
                                  spoken: Self.weekday(start, zone: zone, format: "EEEE"), height: tagHeight)
                    .offset(y: tagY)
            }
        }
    }

    /// "Wed" ("EEE") or "Wednesday" ("EEEE") there.
    static func weekday(_ date: Date, zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// AM/PM and half-hour minutes: 12 pt (was 11), a step above Apple's 11 pt minimum.
    private var suffixFont: Font { .system(size: minorPoints * typeScale, weight: .semibold) }

    /// "9" (12-hour) or "09" (24-hour).
    static func digits(_ hour: Int, use24h: Bool) -> String {
        use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)"
    }

    /// `digits` (`size`, default `digitSize`: 16 pt over AM/PM, else 14), with ":30" inline at a
    /// constant 12 pt medium in half-hour zones (was 0.8x the digits, 11 to 12 pt), as the apps'.
    private func label(_ digits: String, minute: Int, size: CGFloat? = nil, weight: Font.Weight? = nil) -> Text {
        let digitPoints = size ?? (minute != 0 ? (center ? 16 : 14) : digitSize)
        var text = Text(digits)
            .font(.system(size: digitPoints, weight: weight ?? (center ? .semibold : .medium)))
        if minute != 0 {
            text = text + Text(":" + String(format: "%02d", minute))
                .font(.system(size: minorPoints * typeScale, weight: .medium))
        }
        return text.monospacedDigit()
    }

    /// Half-hour tiles: the hour at the row's full digit size, as every other row's (it shrank to
    /// about 12 pt, 24% under them). "8:30" over "PM" (the apps' layout) where "10:30" fits; else
    /// "10" over ":30 PM" at 12 pt where that fits (it does not on a 40 pt tile: ":30 AM" is about
    /// 39 pt against 36); else the shared ladder, where only the hour steps down and ":30" and AM/PM
    /// stay 12 pt. The first two measure "10", so every row and every hour pick the same one.
    @ViewBuilder
    private func halfHourLabel(hour: Int, minute: Int, suffix: String?) -> some View {
        let own = Self.digits(hour, use24h: snapshot.use24h)
        // Measured against a fixed two-digit hour, as the app's HourTiles ("10:30"), not the row's
        // own widest, so the layout never flips from hour to hour or between half-hour cities.
        // (Only reached when stacked, i.e. 12-hour, so the hour is at most two digits.)
        let wide = "10"
        let minutes = ":" + String(format: "%02d", minute)
        ViewThatFits(in: .horizontal) {
            VStack(spacing: -1) {
                fitted(own, wide, minute: minute, size: digitSize)
                if let suffix { suffixText(suffix, size: minorPoints * typeScale) }
            }
            VStack(spacing: -1) {
                fitted(own, wide, minute: 0, size: digitSize)
                minuteLine(minutes, suffix: suffix, size: minorPoints * typeScale)
            }
            VStack(spacing: -1) {
                sharedLabel(hour: hour, minute: minute)
                if let suffix { suffixText(suffix, size: minorPoints * typeScale) }
            }
        }
    }

    private func suffixText(_ suffix: String, size: CGFloat) -> some View {
        Text(suffix)
            .font(.system(size: size, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(1)
    }

    /// ":30 PM", measured as ":30 AM" (the wider) so tiles either side of noon pick the same variant.
    private func minuteLine(_ minutes: String, suffix: String?, size: CGFloat) -> some View {
        let font = Font.system(size: size, weight: .semibold)
        let text = minutes + (suffix.map { "\u{2009}" + $0 } ?? "")
        return ZStack {
            Text(minutes + (suffix == nil ? "" : "\u{2009}AM")).font(font).monospacedDigit().hidden()
            Text(text).font(font).monospacedDigit()
        }
        .lineLimit(1)
    }

    /// The stacked hour at the largest of three sizes (base, −1, −2 pt) at which the row's widest
    /// label (semibold, the now tile's weight) fits, so all three tiles in a row pick the same size;
    /// only if none fits does the label shrink on its own (to 0.85), as before.
    @ViewBuilder
    private func sharedLabel(hour: Int, minute: Int) -> some View {
        let own = Self.digits(hour, use24h: snapshot.use24h)
        let wide = widest.count > own.count ? widest : own
        if minute != 0 {
            // Half-hour zones: the hour starts at the row's digit size, as the full-hour rows' (it
            // started at 14 and fell to 12, 24% under them, beside an 11 pt ":30"), with ":30" at
            // 11 to 12 pt; it steps down only as far as the old 12 pt, then shrinks as before.
            ViewThatFits(in: .horizontal) {
                fitted(own, wide, minute: minute, size: digitSize)
                fitted(own, wide, minute: minute, size: digitSize - 1)
                fitted(own, wide, minute: minute, size: max(12, digitSize - 2))
                fitted(own, wide, minute: minute, size: max(12, digitSize - 3))
                fitted(own, wide, minute: minute, size: 12)
                label(own, minute: minute, size: 12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        } else {
            let base = digitSize
            ViewThatFits(in: .horizontal) {
                fitted(own, wide, minute: minute, size: base)
                fitted(own, wide, minute: minute, size: base - 1)
                fitted(own, wide, minute: minute, size: base - 2)
                label(own, minute: minute, size: base - 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func fitted(_ own: String, _ wide: String, minute: Int, size: CGFloat) -> some View {
        ZStack {
            label(wide, minute: minute, size: size, weight: .semibold).hidden()
            label(own, minute: minute, size: size)
        }
        .lineLimit(1)
    }
}

/// The new day's weekday ("WED") above the tile where the day starts, as the app's DayTag: 11 pt
/// semibold caps, gold on a black 70% pill (was 55%: 2.9:1 over a white sky, now 5.2:1, as the photo
/// behind the tiles is no longer darkened), 5 pt each side of the word (down to 3, so it is never
/// wider than its tile). VoiceOver reads the whole weekday.
private struct WidgetPhotoDayTag: View {
    let weekday: String
    let spoken: String
    var height: CGFloat = 15

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(5)
            pill(4)
            pill(3)
        }
        .accessibilityLabel(spoken)
    }

    private func pill(_ padding: CGFloat) -> some View {
        Text(weekday)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.3)
            .lineLimit(1)
            .foregroundStyle(WidgetTone.midnight)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .fixedSize()
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
        let status = WidgetWorkStatus.of(city, snapshot: snapshot, at: date)
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            WidgetBannerClock(date: date, zone: zone, use24h: snapshot.use24h, size: 34)
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
