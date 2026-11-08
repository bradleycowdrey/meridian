import SwiftUI

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
/// the day at that hour there (warm black at night, greys at dawn and dusk, cream by day), dimmed
/// outside working hours, with the weekday and a crimson mark where a new day starts, and the outer
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
        return VStack(spacing: 1) {
            label(hour: hour, minute: minute, center: k == 0)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if newDay {
                Text(TimeMath.weekday(start, in: place.timeZone))
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(style.text)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Outside working hours the tile lets a little of the panel through, as on the Mac.
        .background(RoundedRectangle(cornerRadius: TileGrid.radius, style: .continuous).fill(style.fill.opacity(dim ? 0.72 : 1)))
        .overlay(alignment: .leading) {
            // Midnight: a crimson mark centred in the gap before the new day, as on the Mac.
            if newDay {
                Capsule()
                    .fill(Theme.crimson)
                    .frame(width: 2)
                    .padding(.vertical, 8)
                    .offset(x: -(TileGrid.gap / 2 + 1))
                    .allowsHitTesting(false)
            }
        }
    }

    /// "9", "09", "9 AM", "5:30 PM" (minutes and AM/PM set small).
    private func label(hour: Int, minute: Int, center: Bool) -> Text {
        let use24h = store.use24h
        var text = Text(use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)")
            .font(.system(size: 16, weight: center ? .semibold : .medium))
        if minute != 0 {
            text = text + Text(":" + String(format: "%02d", minute)).font(.system(size: 11, weight: .medium))
        }
        if !use24h {
            text = text + Text("\u{2009}" + (hour < 12 ? "AM" : "PM")).font(.system(size: minute != 0 ? 8 : 9, weight: .medium))
        }
        return text
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
                shape
                    .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.62), lineWidth: Self.stroke))
                    .shadow(color: Color.white.opacity(0.18), radius: 8)
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
