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
    /// The Now tile (column 0) is this much wider than each other tile (they share the rest
    /// equally; the gaps stay), and `nowGrow` taller above and below their common centre line.
    static let nowWidthFactor: CGFloat = 1.12
    static let nowGrow: CGFloat = 4

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
/// outside working hours, with a small gold weekday tag above the tile where a new day starts, and the
/// outer tiles fading into the panel (not on a city card's photo). The middle column (the hour holding
/// the moment shown) is larger, and marked by one outline down the whole list (`NowCapsule`), which finds the
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
    /// The list's Now outline closes just above this row's Now tile (the first card; the safe default).
    /// False on a card below the first, where the outline only passes either side of the Now tile.
    var outlineAbove = true
    @State private var width: CGFloat = 228
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tile type sizes (as `TileLabel`'s), to decide whether ":30" fits inline in every tile.
    @ScaledMetric(relativeTo: .body) private var digitMetric: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var minuteMetric: CGFloat = 13

    /// The columns shown: all five, or at Accessibility text sizes the hour before, the moment's
    /// hour and the hour after, so their numbers can keep growing (column 0 is always shown).
    private var columns: [Int] { typeSize.isAccessibilitySize ? [-1, 0, 1] : TileGrid.columns }

    /// One column and its gap.
    private var pitch: CGFloat { max(1, (width + TileGrid.gap) / CGFloat(columns.count)) }

    /// Each tile but the Now tile, and the Now tile (`TileGrid.nowWidthFactor` as wide).
    private func otherWidth(_ count: Int) -> CGFloat {
        max(1, (width - TileGrid.gap * CGFloat(count - 1)) / (CGFloat(count - 1) + TileGrid.nowWidthFactor))
    }
    private func nowWidth(_ count: Int) -> CGFloat { otherWidth(count) * TileGrid.nowWidthFactor }

    /// The column under `x`: tile edges as laid out (the Now tile wider), split mid-gap.
    private func column(at x: CGFloat) -> Int {
        let shown = columns
        var edge: CGFloat = 0
        for k in shown {
            edge += (k == 0 ? nowWidth(shown.count) : otherWidth(shown.count)) + TileGrid.gap
            if x < edge - TileGrid.gap / 2 { return k }
        }
        return shown[shown.count - 1]
    }

    var body: some View {
        let starts = TileGrid.starts(store.moment)
        let shown = columns
        let inline = inlineMinutesFit(columns: shown)
        HStack(spacing: TileGrid.gap) {
            ForEach(shown, id: \.self) { k in
                // The Now tile: wider, and taller by `nowGrow` above and below (the row stays
                // `height` tall and centred, so the other tiles keep their place).
                tile(k, start: starts[k + 2], inlineMinutes: inline)
                    .frame(width: k == 0 ? nowWidth(shown.count) : nil,
                           height: k == 0 ? height + 2 * TileGrid.nowGrow : nil)
                    .frame(maxWidth: k == 0 ? nil : CGFloat.infinity)
                    .anchorPreference(key: NowTileAnchors.self, value: .bounds) { anchor in
                        (nowAnchor && k == 0) ? [anchor] : []
                    }
            }
        }
        .frame(height: height)
        .mask {
            // Past the row's top and bottom, so the taller Now tile isn't cut off.
            Group {
                if fade { TileGrid.edgeFade } else { Color.black }
            }
            .padding(.vertical, -TileGrid.nowGrow)
            // And past the top again, for the weekday tag above the tile where a new day starts.
            .padding(.top, -Self.tagReach)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let k = column(at: location.x)
            guard k != 0 || !store.isNow else { return }
            store.jump(to: TileGrid.starts(store.moment)[k + 2])
        }
        .modifier(Scrub(pointsPerHour: pitch))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
        // Where a new day starts in the hour shown, its weekday too ("12:15 AM, Wednesday").
        let anchor = TimeMath.hourAnchor(store.moment)
        let spoken = startsNewDay(anchor) ? "\(time), \(Self.spokenWeekday(anchor, in: place.timeZone))" : time
        guard store.showWorkHours else { return spoken }
        let off = WorkWeek.offLabel(place, at: store.moment, start: store.workStart, end: store.workEnd)
        return "\(spoken), \(off?.lowercased() ?? "working")"
    }

    /// A new day starts in the hour from `start` (usually 00:00, but some clock changes skip midnight).
    private func startsNewDay(_ start: Date) -> Bool {
        !place.calendar.isDate(start, inSameDayAs: start.addingTimeInterval(-3600))
    }

    private static func spokenWeekday(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// How far above the Now tile's top the weekday tag can reach: its height, and its clearance over
    /// the Now outline's top line (the line's centre `NowCapsule.inset` above the tile, half its band,
    /// and 2 pt clear).
    static let tagClearance: CGFloat = NowCapsule.inset + NowCapsule.band / 2 + 2
    static let tagReach: CGFloat = DayTag.height + tagClearance

    /// The card is too short for the tag above its tiles (it has shrunk them: only its top padding is
    /// left above), so the tag goes inside the tile's top edge instead.
    private var tagInside: Bool { height < RowCard.tileHeight }

    /// The weekday tag's top, from its tile's top: above the tile with 3 pt between them; above the
    /// Now outline's top line with 2 pt clear where that passes over the Now tile; or 2 pt inside the
    /// tile on a card too short for either.
    private func tagOffset(_ k: Int) -> CGFloat {
        if tagInside { return 2 }
        let gap: CGFloat = (k == 0 && nowAnchor && outlineAbove) ? Self.tagClearance : 3
        return -(DayTag.height + gap)
    }

    /// Half-hour zones: whether ":30" fits inline after the hour ("7:30", as on the widgets and on
    /// Android). Measured on the widest label any hour can take (two digits, as "10:30"; digits are
    /// tabular), so the answer depends only on the tile width and text size: the row never switches
    /// layout while you scrub, and "9:30" and "10:30" side by side never differ. Where it doesn't
    /// fit (five tiles on an iPhone), every tile puts its minutes on their own line.
    private func inlineMinutesFit(columns: [Int]) -> Bool {
        let large = typeSize.isAccessibilitySize
        // Each tile's width less its 2 pt padding each side, and 1 pt to spare: the other tiles at
        // their type sizes, and the wider Now tile at its larger ones.
        func fits(room: CGFloat, bump: CGFloat, minuteBump: CGFloat) -> Bool {
            let digitFont = UIFont.monospacedDigitSystemFont(ofSize: TileLabel.digitSize(digitMetric, large: large) + bump, weight: .semibold)
            let minuteFont = UIFont.monospacedDigitSystemFont(ofSize: TileLabel.minuteSize(minuteMetric, large: large) + minuteBump, weight: .semibold)
            let needed = ("00" as NSString).size(withAttributes: [.font: digitFont]).width
                + (":00" as NSString).size(withAttributes: [.font: minuteFont]).width
            return needed.rounded(.up) <= room
        }
        return fits(room: otherWidth(columns.count) - 5, bump: 0, minuteBump: 0)
            && fits(room: nowWidth(columns.count) - 5, bump: TileLabel.nowDigitBump, minuteBump: TileLabel.nowLabelBump)
    }

    private func tile(_ k: Int, start: Date, inlineMinutes: Bool) -> some View {
        let cal = place.calendar
        let parts = cal.dateComponents([.hour, .minute], from: start)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        // One flat colour per tile: the day there at the tile's start, as on the Mac.
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        // A new day starts in this tile (usually 00:00, but some clock changes skip midnight).
        let newDay = startsNewDay(start)
        let tileWidth = k == 0 ? nowWidth(columns.count) : otherWidth(columns.count)
        let dim = store.showWorkHours && !store.isWorking(place, at: start.addingTimeInterval(1800))
        return TileLabel(hour: hour, minute: minute, use24h: store.use24h, center: k == 0,
                         large: typeSize.isAccessibilitySize,
                         inlineMinutes: inlineMinutes)
            .contentTransition(.numericText())
            .foregroundStyle(style.text)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Outside working hours the tile is the same sky, deeper (opaque, so a photo never shows
            // behind the numbers): working hours stand out from the rest at a glance.
            .background(RoundedRectangle(cornerRadius: TileGrid.radius, style: .continuous)
                .fill(dim ? Self.offHours(style.fill)
                      : store.showWorkHours ? Self.working(style.fill) : Self.legible(style.fill)))
            // Night and off-hours tiles are near-black, close to a night photo: a 1 pt edge (white at
            // 32%) keeps the row of five readable as tiles there (was 0.5 pt at 16%, 1.3:1).
            .overlay(RoundedRectangle(cornerRadius: TileGrid.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(dim || hour < 6 || hour >= 21 ? 0.32 : 0), lineWidth: 1))
            .overlay(alignment: .top) {
                // A new day: its weekday in a small gold tag centred above the tile (the tile itself
                // reads "12", "AM" like its neighbours). Never wider than the tile, so it stays clear
                // of the Now outline's lines either side.
                if newDay {
                    let weekday = TimeMath.weekday(start, in: place.timeZone)
                    DayTag(weekday: weekday, padding: DayTag.padding(for: weekday, tileWidth: tileWidth))
                        .offset(y: tagOffset(k))
                }
            }
    }

    /// The brightest a tile may be (relative luminance): white text on it stays at least 5.5:1.
    static let maxLuminance = 0.14

    /// An hour outside working hours: the tile's sky at 30% of its (capped) luminance and never
    /// brighter than `offHoursCap`, so the midday working tile (#3A6699, 0.127) stands 3.2:1 from
    /// it (was 1.6:1 at 55%) and who is working reads at a glance; never darker than the night tile
    /// (#0A0E1C), so it still reads as a tile on a dark photo (with its hairline).
    static let offHoursFactor = 0.30
    static let offHoursCap = 0.006
    static let offHoursFloor = 0.0048

    static func offHours(_ fill: Color) -> Color {
        scaled(legible(fill)) { l in max(min(l, offHoursFloor), min(l * offHoursFactor, offHoursCap)) }
    }

    /// The tile's sky colour, kept to its hue but darkened where the ramp is brightest (midday and
    /// early evening), so white numbers on it always read.
    static func legible(_ fill: Color) -> Color {
        scaled(fill) { l in min(l, maxLuminance) }
    }

    /// A working hour, while working hours are shown: the legible sky, never darker than
    /// `workingFloor`. The shoulder hours (8–9:30 and 17:30–19) come from the ramp's darker part
    /// (9 AM #2C5386, L 0.084, only 2.4:1 against the 0.006 off tile beside it); at 0.12 every
    /// working tile stands 3.05:1 from an off tile, and white on it stays 6.2:1.
    static let workingFloor = 0.12

    static func working(_ fill: Color) -> Color {
        scaled(fill) { l in min(max(l, workingFloor), maxLuminance) }
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
/// and the minutes in half-hour zones. Midnight and noon read as every other hour ("12", "AM" and
/// "12", "PM"); the new day's weekday is `DayTag`, above the tile.
/// Sizes follow the reader's text size (never below 17 pt digits and 13 pt minutes and labels; at
/// Accessibility sizes, where the row shows three tiles, up to 26 pt digits and 16 pt labels).
/// Every tile has the same lines (hour, then AM/PM), so its digits line up with its
/// neighbours'. In half-hour zones ":30" follows the hour inline, smaller, as on the widgets and on
/// Android, when the whole row fits it; otherwise the row puts its minutes on their own line. When
/// a tile can't hold everything it drops AM/PM, rather than shrinking the type.
private struct TileLabel: View {
    let hour: Int
    let minute: Int
    let use24h: Bool
    let center: Bool
    /// Three wide tiles (Accessibility text sizes): the type may grow further.
    var large = false
    /// ":30" inline after the hour (decided for the whole row by `HourTiles`).
    var inlineMinutes = true

    @ScaledMetric(relativeTo: .body) private var digitMetric: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var minuteMetric: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var smallMetric: CGFloat = 13

    static func digitSize(_ metric: CGFloat, large: Bool) -> CGFloat { min(max(metric, 17), large ? 26 : 21) }
    static func minuteSize(_ metric: CGFloat, large: Bool) -> CGFloat { min(max(metric, 13), large ? 17 : 15) }
    /// The Now tile's type over the others': digits +3 pt; ":30" and AM/PM +1 pt.
    static let nowDigitBump: CGFloat = 3
    static let nowLabelBump: CGFloat = 1

    private var digitSize: CGFloat { Self.digitSize(digitMetric, large: large) + (center ? Self.nowDigitBump : 0) }
    private var minuteSize: CGFloat { Self.minuteSize(minuteMetric, large: large) + (center ? Self.nowLabelBump : 0) }
    private var smallSize: CGFloat { min(max(smallMetric, 13), large ? 16 : 14) + (center ? Self.nowLabelBump : 0) }

    var body: some View {
        ViewThatFits {
            // "5", "PM" (or "5:30", "PM"); midnight "12", "AM" and noon "12", "PM", like the rest.
            variant(suffix: true)
            // Without AM/PM (the least needed: the neighbouring tiles carry it).
            variant(suffix: false)
            // Last resort: the hour line may shrink a little (never below 90%).
            hourLine(inlineMinutes: true)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func variant(suffix: Bool) -> some View {
        VStack(spacing: 0) {
            hourLine(inlineMinutes: inlineMinutes)
            if minute != 0 && !inlineMinutes { minuteText }
            if suffix, !use24h {
                Text(hour < 12 ? "AM" : "PM")
                    .font(.system(size: smallSize, weight: .semibold))
                    .tracking(0.3)
            }
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

}

/// The new day's weekday ("WED"), above the tile where the day starts: gold on a dark pill, the same
/// on every platform. A fixed 11 pt, so it always fits above the tile inside the card.
private struct DayTag: View {
    let weekday: String
    /// Each side of the word (5 pt, less on a narrow tile).
    let padding: CGFloat

    static let height: CGFloat = 15
    static let fontSize: CGFloat = 11
    static let tracking: CGFloat = 0.3

    /// 5 pt each side, or less (never under 3) so the tag is no wider than its tile.
    static func padding(for weekday: String, tileWidth: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        let word = (weekday.uppercased() as NSString).size(withAttributes: attributes).width
        return min(5, max(3, (tileWidth - word) / 2))
    }

    var body: some View {
        Text(weekday.uppercased())
            .font(.system(size: Self.fontSize, weight: .semibold))
            .tracking(Self.tracking)
            .lineLimit(1)
            .foregroundStyle(Theme.midnight)
            .padding(.horizontal, padding)
            .frame(height: Self.height)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// The middle tiles' frames (the hour holding the moment shown), from every city card on the list.
struct NowTileAnchors: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// One "Now" outline down the list, as on the app icon: round the middle tile of every card, from
/// just above the first to just below the last, over the list's content so it scrolls with the
/// cards. A rounded rectangle concentric with the Now tiles: its line runs midway in the gap between
/// them and their neighbours, and its corners follow the tiles' corners. It follows the moment shown
/// (it is always on the middle column), never takes a touch, and VoiceOver skips it.
struct NowCapsule: View {
    let anchors: [Anchor<CGRect>]
    /// The line's centre runs this far outside the Now tiles on every side: half the gap to their
    /// neighbours, so it sits midway between the tiles it encloses and those it doesn't.
    static let inset: CGFloat = TileGrid.gap / 2
    /// Concentric with the tiles' corners (never width / 2).
    static let radius: CGFloat = TileGrid.radius + inset
    /// The white line, and the dark edge (60% black) each side of it that keeps it 3:1 or better
    /// where it crosses a bright day sky. Together within the gap less 1 pt, so 0.5 pt or more of the
    /// gap stays clear to the tiles each side (gap 6: 2 pt white, 1 pt dark each side, 1 pt clear).
    static let core: CGFloat = min(2, max(1, TileGrid.gap - 2))
    static let edge: CGFloat = min(1, max(0.5, (TileGrid.gap - 1 - core) / 2))
    static let band: CGFloat = core + 2 * edge

    var body: some View {
        GeometryReader { proxy in
            if let frame = Self.capsuleFrame(anchors.map { proxy[$0] }, in: proxy.size) {
                let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                // A stroke only, centred on the outline's line (`stroke`, not `strokeBorder`): no fill
                // or glow over the tiles, so they keep their own colour and their numbers' contrast.
                ZStack {
                    shape.stroke(Color.black.opacity(0.6), lineWidth: Self.band)
                    shape.stroke(Color.white.opacity(0.85), lineWidth: Self.core)
                }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The outline's centre line: the Now tiles' column widened by `inset` each side, from `inset`
    /// above the topmost to `inset` below the lowest, kept (with its stroke) inside the content.
    static func capsuleFrame(_ tiles: [CGRect], in size: CGSize) -> CGRect? {
        guard let first = tiles.first, size.width > 0, size.height > 0, first.width > 0 else { return nil }
        let half = band / 2
        let left = max(half, first.minX - inset)
        let right = min(size.width - half, first.maxX + inset)
        let top = max(half, (tiles.map(\.minY).min() ?? first.minY) - inset)
        let bottom = min(size.height - half, (tiles.map(\.maxY).max() ?? first.maxY) + inset)
        guard right - left > 1, bottom - top > 1 else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
