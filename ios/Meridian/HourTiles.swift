import SwiftUI

/// The five hour columns every row shares (two hours back, the hour holding the selected moment,
/// two ahead), as in Meridian for Mac. Column 0 always holds the moment.
enum TileGrid {
    /// One even gutter between tiles and between rows, as on the Mac.
    static let gap: CGFloat = 6
    static let height: CGFloat = 44
    static let radius: CGFloat = 9
    static let lensStroke: CGFloat = 2
    /// The lens's stroke sits centred in the gutter around the tile, as on the Mac.
    static let lensOutset: CGFloat = gap / 2 + lensStroke / 2
    /// Concentric with the tiles' corners.
    static let lensRadius: CGFloat = radius + lensOutset
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
/// left, five hour tiles on the right. The column labels at the top line up with the tiles.
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
/// tiles fading into the panel. With `lens`, the white lens marks the middle column.
/// Tap a tile to go to that hour; drag to scrub.
struct HourTiles: View {
    @EnvironmentObject private var store: CityStore
    let place: Place
    /// The tiles' height (taller under a city card's banner).
    var height: CGFloat = TileGrid.height
    /// Draw the white lens around the middle tile here (each city card has its own).
    var lens = false
    @State private var width: CGFloat = 228

    /// One column and its gap.
    private var pitch: CGFloat { max(1, (width + TileGrid.gap) / CGFloat(TileGrid.columns.count)) }

    var body: some View {
        let starts = TileGrid.starts(store.moment)
        HStack(spacing: TileGrid.gap) {
            ForEach(TileGrid.columns, id: \.self) { k in
                tile(k, start: starts[k + 2])
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .mask { TileGrid.edgeFade }
        .overlay(alignment: .topLeading) {
            if lens { lensOutline }
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

    /// The white lens around the hour holding the selected moment, centred in the gutter around it.
    private var lensOutline: some View {
        let o = TileGrid.lensOutset
        let shape = RoundedRectangle(cornerRadius: TileGrid.lensRadius, style: .continuous)
        return shape.fill(Color.white.opacity(0.06))
            .overlay(shape.strokeBorder(Color.white, lineWidth: TileGrid.lensStroke))
            .frame(width: max(0, pitch - TileGrid.gap + 2 * o), height: height + 2 * o)
            .offset(x: 2 * pitch - o, y: -o)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// The column labels, drawn once over every row's tiles in the bar under the title: "Now" (or
/// the selected time) in the middle, and −2/−1/+1/+2 hr as small buttons either side. A short white
/// line under a column says everyone on the list is working then.
struct ColumnHeader: View {
    @EnvironmentObject private var store: CityStore
    /// The bar's width, so the labels line up with the rows' tiles.
    @State private var width: CGFloat = 390

    var body: some View {
        let starts = TileGrid.starts(store.moment)
        let nowAnchor = TimeMath.hourAnchor(store.now)
        HStack(spacing: TileGrid.gap) {
            ForEach(TileGrid.columns, id: \.self) { k in
                column(k, start: starts[k + 2], nowAnchor: nowAnchor)
            }
        }
        // Over the tiles: past the name column, to the panel's inner edge.
        .padding(.leading, Strip.edge + Strip.labelWidth(max(0, width - 2 * Strip.edge)) + Strip.labelGap)
        .padding(.trailing, Strip.edge)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func column(_ k: Int, start: Date, nowAnchor: Date) -> some View {
        // A side column holding the current hour reads "Now" (after travelling a little).
        let readsNow = k != 0 && !store.isNow && start == nowAnchor
        let plain = k == 0 || readsNow
        let centreAtNow = k == 0 && store.isNow
        return Button {
            tap(k, start: start, readsNow: readsNow)
        } label: {
            VStack(spacing: 3) {
                Text(label(k, readsNow: readsNow))
                    .font(.system(size: 13, weight: plain ? .semibold : .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.white.opacity(readsNow ? 0.9 : 1))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background {
                        if !plain { Capsule().fill(Color.white.opacity(0.08)) }
                    }
                Capsule()
                    .fill(Color.white)
                    .frame(width: 16, height: 3)
                    .opacity(overlap(start) ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        // At now the middle does nothing, but stays fully white (not greyed as disabled).
        .allowsHitTesting(!centreAtNow)
        .accessibilityLabel(accessibilityLabel(k, start: start, readsNow: readsNow))
        .accessibilityAddTraits(centreAtNow ? .isSelected : [])
    }

    private func label(_ k: Int, readsNow: Bool) -> String {
        if k == 0 { return store.isNow ? "Now" : TimeMath.time(store.moment, in: .current, use24h: store.use24h) }
        if readsNow { return "Now" }
        return k > 0 ? "+\(k) hr" : "\u{2212}\(-k) hr"
    }

    private func tap(_ k: Int, start: Date, readsNow: Bool) {
        if k == 0 || readsNow {
            if !store.isNow { store.backToNow() }
        } else if store.isNow {
            // As the old hour buttons: moves with the clock.
            store.shift(minutes: k * 60)
        } else {
            store.jump(to: start)
        }
    }

    private func accessibilityLabel(_ k: Int, start: Date, readsNow: Bool) -> String {
        if k == 0 { return store.isNow ? "Now" : "Back to now" }
        if readsNow { return "Back to now" }
        if store.isNow { return TimeShifter.describe(k * 60) }
        let hours = abs(k) == 1 ? "1 hour" : "\(abs(k)) hours"
        return "\(hours) \(k > 0 ? "later" : "earlier"), \(TimeMath.time(start, in: .current, use24h: store.use24h))"
    }

    /// Everyone on the list is working through this column's middle.
    private func overlap(_ start: Date) -> Bool {
        let places = store.visiblePlaces
        guard store.showWorkHours, places.count >= 2 else { return false }
        let middle = start.addingTimeInterval(1800)
        return places.allSatisfy { store.isWorking($0, at: middle) }
    }
}
