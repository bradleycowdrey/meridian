import SwiftUI
import UIKit

/// The five hour columns every row shares (two hours back, the hour holding the selected moment,
/// two ahead), as in Meridian for Mac. Column 0 always holds the moment.
enum TileGrid {
    /// One even gutter between tiles and between rows, as on the Mac.
    static let gap: CGFloat = 6
    static let height: CGFloat = 44
    static let radius: CGFloat = 9
    static let columns = [-2, -1, 0, 1, 2]

    /// Each column's start: whole hours on your clock around the moment.
    static func starts(_ moment: Date) -> [Date] {
        let anchor = TimeMath.hourAnchor(moment)
        return columns.map { anchor.addingTimeInterval(Double($0) * 3600) }
    }

    /// The Mac's edge fade: the outer tiles fade softly into the panel.
    static var edgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.11),
                .init(color: .black, location: 0.89),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

/// The cities as rows in one rounded panel, as in Meridian for Mac: the name and time on the
/// left, five hour tiles on the right.
enum Strip {
    /// Screen edge to panel.
    static let margin: CGFloat = 12
    /// Panel edge to its rows.
    static let inset: CGFloat = 10
    /// Space above and below the panel.
    static let lead: CGFloat = 8
    static let radius: CGFloat = 20
    /// Between the city's name and its tiles.
    static let labelGap: CGFloat = 8
    /// Screen edge to a row's content.
    static let edge: CGFloat = margin + inset

    /// The name column's width for a row `content` wide (the tiles take the rest).
    static func labelWidth(_ content: CGFloat) -> CGFloat {
        min(150, max(100, (content * 0.40).rounded(.down)))
    }

    /// One tile and its gap, in a row `content` wide.
    static func pitch(_ content: CGFloat) -> CGFloat {
        let tiles = content - labelWidth(content) - labelGap
        return max(1, (tiles + TileGrid.gap) / CGFloat(TileGrid.columns.count))
    }
}

/// One row's share of the panel behind the cities: the top row rounds the top corners, the last
/// row the bottom ones, so the rows read as one panel.
struct PanelSegment: View {
    let first: Bool
    let last: Bool

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: first ? Strip.radius : 0,
                               bottomLeadingRadius: last ? Strip.radius : 0,
                               bottomTrailingRadius: last ? Strip.radius : 0,
                               topTrailingRadius: first ? Strip.radius : 0,
                               style: .continuous)
            .fill(Theme.tile)
            .padding(.top, first ? Strip.lead : 0)
            .padding(.bottom, last ? Strip.lead : 0)
            .padding(.horizontal, Strip.margin)
    }
}

/// Sideways drag to scrub through time in quarter-hours. Locks to the first direction moved, so
/// vertical drags still scroll the list.
struct Scrub: ViewModifier {
    @EnvironmentObject private var store: CityStore
    let pointsPerHour: CGFloat
    @State private var base: Int?
    @State private var horizontal: Bool?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag in
                    if horizontal == nil { horizontal = abs(drag.translation.width) > abs(drag.translation.height) }
                    guard horizontal == true else { return }
                    let start = base ?? store.offsetMinutes
                    base = start
                    let minutes = -Double(drag.translation.width) / Double(pointsPerHour) * 60
                    store.scrub(toQuarterNear: Double(start) + minutes)
                }
                .onEnded { _ in
                    base = nil
                    horizontal = nil
                }
        )
    }
}

/// A city's hours as five day-and-night tiles, as in Meridian for Mac: each tile the colour of
/// the day at that hour there (navy at night, deep blues at dawn and dusk, sky blue by day), dimmed
/// outside working hours, with the weekday and a gold mark where a new day starts, and the outer
/// tiles fading into the panel (not on a city card's photo). The middle column (the hour holding
/// the moment shown) is marked by one capsule down the whole list (`NowCapsule`), which finds the
/// middle tiles through `NowTileAnchors`. Tap a tile to go to that hour; drag to scrub.
struct HourTiles: View {
    @EnvironmentObject private var store: CityStore
    let place: Place
    /// The tiles' height (taller on a city card).
    var height: CGFloat = TileGrid.height
    /// Report the middle tile's frame for the list's Now capsule.
    var nowAnchor = false
    /// Fade the outer tiles into the panel behind (off on a photo).
    var fade = true
    @State private var width: CGFloat = 228

    /// One column and its gap.
    private var pitch: CGFloat { max(1, (width + TileGrid.gap) / CGFloat(TileGrid.columns.count)) }

    var body: some View {
        let starts = TileGrid.starts(store.moment)
        HStack(spacing: TileGrid.gap) {
            ForEach(TileGrid.columns, id: \.self) { k in
                tile(k, start: starts[k + 2])
                    .frame(maxWidth: .infinity)
                    .anchorPreference(key: NowTileAnchors.self, value: .bounds) { anchor in
                        (nowAnchor && k == 0) ? [anchor] : []
                    }
            }
        }
        .frame(height: height)
        .mask {
            if fade { TileGrid.edgeFade } else { Color.black }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let k = min(max(Int(location.x / pitch), 0), TileGrid.columns.count - 1) - 2
            guard k != 0 || !store.isNow else { return }
            store.jump(to: TileGrid.starts(store.moment)[k + 2])
        }
        .modifier(Scrub(pointsPerHour: pitch))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hours in \(place.title)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.travel(1)
            case .decrement: store.travel(-1)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        let time = TimeMath.time(store.moment, in: place.timeZone, use24h: store.use24h)
        guard store.showWorkHours else { return time }
        let off = WorkWeek.offLabel(place, at: store.moment, start: store.workStart, end: store.workEnd)
        return "\(time), \(off?.lowercased() ?? "working")"
    }

    private func tile(_ k: Int, start: Date) -> some View {
        let cal = place.calendar
        let parts = cal.dateComponents([.hour, .minute], from: start)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        // One flat colour per tile: the day there at the tile's start, as on the Mac.
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        // A new day starts in this tile (usually 00:00, but some clock changes skip midnight).
        let newDay = !cal.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
        let dim = store.showWorkHours && !store.isWorking(place, at: start.addingTimeInterval(1800))
        return TileLabel(hour: hour, minute: minute, use24h: store.use24h, center: k == 0,
                         weekday: newDay ? TimeMath.weekday(start, in: place.timeZone) : nil)
            .contentTransition(.numericText())
            .foregroundStyle(style.text)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Outside working hours the tile is the same sky, deeper (opaque, so a photo never shows
            // behind the numbers): working hours stand out from the rest at a glance.
            .background(RoundedRectangle(cornerRadius: TileGrid.radius, style: .continuous)
                .fill(dim ? Self.offHours(style.fill) : Self.legible(style.fill)))
            .overlay(alignment: .leading) {
                // Midnight: a sunrise-gold mark centred in the gap before the new day, as on the Mac.
                if newDay {
                    Capsule()
                        .fill(Theme.midnight)
                        .frame(width: 2)
                        .padding(.vertical, 8)
                        .offset(x: -(TileGrid.gap / 2 + 1))
                        .allowsHitTesting(false)
                }
            }
    }

    /// The brightest a tile may be (relative luminance): white text on it stays at least 5.5:1.
    static let maxLuminance = 0.14

    /// An hour outside working hours: the tile's sky at 55% of its (capped) luminance, never darker
    /// than the night tile (#0A0E1C), so it still reads as a tile on a dark photo.
    static let offHoursFactor = 0.55
    static let offHoursFloor = 0.0048

    static func offHours(_ fill: Color) -> Color {
        scaled(legible(fill)) { l in max(min(l, offHoursFloor), l * offHoursFactor) }
    }

    /// The tile's sky colour, kept to its hue but darkened where the ramp is brightest (midday and
    /// early evening), so white numbers on it always read.
    static func legible(_ fill: Color) -> Color {
        scaled(fill) { l in min(l, maxLuminance) }
    }

    /// `fill` with its relative luminance mapped by `target`, keeping its hue.
    private static func scaled(_ fill: Color, _ target: (Double) -> Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(fill).getRed(&r, green: &g, blue: &b, alpha: &a) else { return fill }
        func linear(_ c: CGFloat) -> Double {
            let c = Double(min(max(c, 0), 1))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func encoded(_ l: Double) -> Double {
            l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        }
        let lr = linear(r), lg = linear(g), lb = linear(b)
        let luminance = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
        guard luminance > 0 else { return fill }
        let goal = target(luminance)
        guard abs(goal - luminance) > 1e-6 else { return fill }
        let k = goal / luminance
        return Color(.sRGB, red: encoded(lr * k), green: encoded(lg * k), blue: encoded(lb * k), opacity: Double(a))
    }
}

/// One tile's words, as on the widgets: the hour in large tabular digits with AM or PM under it,
/// the minutes in half-hour zones, and the weekday where a new day starts. Sizes follow the
/// reader's text size (never below 17 pt digits and 12 pt labels, up to the tiles' xxLarge cap).
/// In half-hour zones the minutes always sit on their own line under the hour, so the layout never
/// depends on how wide a tile's digits are. When a tile can't hold everything it drops AM/PM, rather
/// than shrinking the type.
private struct TileLabel: View {
    let hour: Int
    let minute: Int
    let use24h: Bool
    let center: Bool
    let weekday: String?

    @ScaledMetric(relativeTo: .body) private var digitMetric: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var minuteMetric: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var smallMetric: CGFloat = 12

    private var digitSize: CGFloat { min(max(digitMetric, 17), 21) }
    private var minuteSize: CGFloat { min(max(minuteMetric, 12), 15) }
    private var smallSize: CGFloat { min(max(smallMetric, 12), 14) }

    var body: some View {
        ViewThatFits {
            // "5", ":30", "PM". Minutes always get their own line, so every tile in a row has
            // the same layout whatever the width of its own digits ("1:30" next to "12:30").
            variant(inlineMinutes: false, suffix: true)
            // Digits only (AM/PM is the least needed: the neighbouring tiles carry it).
            variant(inlineMinutes: false, suffix: false)
            // Last resort: the hour line may shrink a little (never below 90%).
            VStack(spacing: 0) {
                hourLine(inlineMinutes: true)
                    .minimumScaleFactor(0.9)
                if let weekday { weekdayText(weekday) }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    private func variant(inlineMinutes: Bool, suffix: Bool) -> some View {
        VStack(spacing: 0) {
            hourLine(inlineMinutes: inlineMinutes)
            if minute != 0 && !inlineMinutes { minuteText }
            if suffix, !use24h {
                Text(hour < 12 ? "AM" : "PM")
                    .font(.system(size: smallSize, weight: .semibold))
                    .tracking(0.3)
            }
            if let weekday { weekdayText(weekday) }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    private func hourLine(inlineMinutes: Bool) -> Text {
        let digits = Text(use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)")
            .font(.system(size: digitSize, weight: center ? .semibold : .medium))
        return (minute != 0 && inlineMinutes) ? digits + minuteText : digits
    }

    private var minuteText: Text {
        Text(":" + String(format: "%02d", minute)).font(.system(size: minuteSize, weight: .semibold))
    }

    private func weekdayText(_ weekday: String) -> Text {
        Text(weekday.uppercased())
            .font(.system(size: smallSize, weight: .medium))
            .tracking(0.3)
    }
}

/// The middle tiles' frames (the hour holding the moment shown), from every city card on the list.
struct NowTileAnchors: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// One "Now" capsule down the list, as on the app icon: through the middle tile of every card,
/// from just above the first to just below the last, over the list's content so it scrolls with
/// the cards. It follows the moment shown (it is always on the middle column), never takes a
/// touch, and VoiceOver skips it.
struct NowCapsule: View {
    let anchors: [Anchor<CGRect>]
    /// Past the tile on each side.
    static let outset: CGFloat = 7
    /// Above the first card's tile and below the last one's.
    static let overhang: CGFloat = 12
    static let stroke: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            if let frame = Self.capsuleFrame(anchors.map { proxy[$0] }, in: proxy.size) {
                let shape = Capsule(style: .continuous)
                // A stroke only: no fill or glow over the middle tiles, so they keep their own
                // colour and their numbers' contrast.
                shape
                    .strokeBorder(Color.white.opacity(0.62), lineWidth: Self.stroke)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The capsule's frame: the middle tiles' column widened by `outset` each side, from
    /// `overhang` above the topmost to `overhang` below the lowest, kept inside the content.
    static func capsuleFrame(_ tiles: [CGRect], in size: CGSize) -> CGRect? {
        guard let first = tiles.first, size.width > 0, size.height > 0, first.width > 0 else { return nil }
        let inset = stroke / 2
        let left = max(inset, first.minX - outset)
        let right = min(size.width - inset, first.maxX + outset)
        let top = max(inset, (tiles.map(\.minY).min() ?? first.minY) - overhang)
        let bottom = min(size.height - inset, (tiles.map(\.maxY).max() ?? first.maxY) + overhang)
        guard right - left > 1, bottom - top > 1 else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
