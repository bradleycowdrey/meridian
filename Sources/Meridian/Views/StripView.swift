import SwiftUI
import AppKit

/// Day-and-night ribbons, one row per city, each on a card of the city's own skyline. Every column
/// is the same instant everywhere, so "now" (or any travelled-to hour) reads as one straight line
/// down the centre: a larger tile in every row, and one outline around them all.
struct StripView: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    var cellWidth: CGFloat = 52
    var rowHeight: CGFloat = 84
    var labelWidth: CGFloat = 200
    /// Clear space between a row's label and its hour tiles: the city's photo is centred here.
    var gapWidth: CGFloat = 170
    var editing = false

    /// Live drag distance; resets by itself if the gesture is cancelled (panel closed mid-drag).
    @GestureState private var drag: CGFloat = 0
    @State private var hoverIndex: Int?
    private var rowSpacing: CGFloat { ui.gutter }
    private var cellGap: CGFloat { ui.gutter }
    /// Column header: hours from now ("−5 … Now … +2") with the meeting-overlap mark beneath.
    private var overlapRowHeight: CGFloat { ui.pt(20) }

    private var pitch: CGFloat { rowHeight + rowSpacing }

    var body: some View {
        GeometryReader { geo in
            let stripWidth = max(cellWidth * 5, geo.size.width - labelWidth - gapWidth)
            let half = Int(stripWidth / cellWidth / 2) + 2
            let total = Double(store.offsetHours) - Double(drag / cellWidth)
            let base = Int(total.rounded())
            let frac = total - Double(base)
            let anchor = TimeMath.hourAnchor(store.now)
            let moment = base == 0 ? store.now : anchor.addingTimeInterval(Double(base) * 3600)
            let tile = cellWidth - cellGap
            let tileHeight = ui.tileHeight(row: rowHeight)
            // Extra room either side of the Now tile, where the outline's line runs.
            let nowPad = ui.nowPad(cell: cellWidth)
            // Under the tiles there is always room for the outline's bottom line inside the row.
            let lensReach: CGFloat = (tileHeight * (ui.nowScale - 1) / 2 + ui.lensInset(tile: tile)
                + ui.lensCore / 2 + ui.lensEdge).rounded(.up)
            let tileBottom = max(0, min(max(ui.tileBottom(row: rowHeight), lensReach), rowHeight - tileHeight))
            let cardWidth = labelWidth + gapWidth + stripWidth + 2 * ui.cardOutset
            // The photo's centre: the middle of the clear gap, from the card's leading edge.
            let focusX = ui.cardOutset + labelWidth + gapWidth / 2

            ZStack(alignment: .topLeading) {
                // Each city's photo (day or night by the sun there at the shown moment), behind
                // its row and reaching a little past it on both sides.
                VStack(spacing: rowSpacing) {
                    ForEach(store.places) { place in
                        MacSkylineBackdrop(name: place.name, timeZoneID: place.timeZoneID,
                                           latitude: place.latitude, longitude: place.longitude,
                                           date: moment, maxPixel: 1000, focusX: focusX)
                            .overlay(scrim(textEnd: ui.cardOutset + labelWidth, cardWidth: cardWidth))
                            .clipShape(RoundedRectangle(cornerRadius: ui.cardRadius, style: .continuous))
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                    }
                }
                .padding(.top, overlapRowHeight + rowSpacing)
                .padding(.horizontal, -ui.cardOutset)
                .frame(width: labelWidth + gapWidth + stripWidth, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        Color.clear.frame(height: overlapRowHeight)
                        ForEach(store.places) { place in
                            PlaceLabel(place: place, moment: moment, editing: editing, pitch: pitch, rowHeight: rowHeight)
                                .frame(width: labelWidth - ui.m, height: rowHeight, alignment: .bottomLeading)
                        }
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    // Above the strip, so the city controls (delete, drag handle) always get the click.
                    .zIndex(1)

                    ZStack(alignment: .top) {
                        VStack(spacing: rowSpacing) {
                            HStack(spacing: cellGap) {
                                ForEach((base - half)...(base + half), id: \.self) { index in
                                    ColumnHeader(
                                        hoursFromNow: index,
                                        isCenter: index == base,
                                        isOverlap: allWorking(at: anchor.addingTimeInterval(Double(index) * 3600))
                                    )
                                    .frame(width: tile, height: overlapRowHeight)
                                    .padding(.horizontal, index == base ? nowPad : 0)
                                }
                            }
                            ForEach(store.places) { place in
                                HStack(spacing: cellGap) {
                                    ForEach((base - half)...(base + half), id: \.self) { index in
                                        let date = anchor.addingTimeInterval(Double(index) * 3600)
                                        HourCell(
                                            date: date,
                                            zone: place.timeZone,
                                            use24h: store.use24h,
                                            dimmed: store.showWorkHours && !store.isWorking(place, at: date),
                                            highlights: store.showWorkHours,
                                            isCenter: index == base,
                                            firstRow: place.id == store.places.first?.id,
                                            width: tile,
                                            tileHeight: tileHeight,
                                            tileBottom: tileBottom,
                                            tileTop: rowHeight - tileBottom - tileHeight,
                                            hovered: hoverIndex == index && index != base
                                        )
                                        // The cell is the whole column of the row, so a click
                                        // anywhere in it picks that hour; the tile sits inside.
                                        .frame(width: tile, height: rowHeight)
                                        .contentShape(Rectangle())
                                        .onHover { inside in
                                            if inside { hoverIndex = index } else if hoverIndex == index { hoverIndex = nil }
                                        }
                                        .onTapGesture { store.travel(index - store.offsetHours) }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                        .testID("hour-\(place.name)-\(index)")
                                        .padding(.horizontal, index == base ? nowPad : 0)
                                        // The larger Now tile overlaps its neighbours' gutters.
                                        .zIndex(index == base ? 1 : 0)
                                    }
                                }
                            }
                        }
                        .offset(x: -CGFloat(frac) * cellWidth)
                        .frame(width: stripWidth)

                        // The Now outline: one line down every row around the Now tiles, shaped
                        // like them (concentric corners) and midway in the gap to their
                        // neighbours. A white core with a thin dark edge; no fill.
                        nowOutline(tile: tile, tileHeight: tileHeight, tileBottom: tileBottom)
                    }
                    .frame(width: stripWidth)
                    .clipped()
                    // Clipping hides the off-screen hour tiles but doesn't stop them catching clicks;
                    // limit hit-testing to the visible strip so they can't cover the city column.
                    .contentShape(Rectangle())
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.11),
                                .init(color: .black, location: 0.89),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .updating($drag) { value, state, _ in state = value.translation.width }
                            .onEnded { value in
                                let hours = Int((-value.translation.width / cellWidth).rounded())
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    store.offsetHours += hours
                                }
                            }
                    )
                    .onScrollWheel { delta in store.travel(delta) }
                    .padding(.leading, gapWidth)
                }
            }
        }
        .frame(height: overlapRowHeight + CGFloat(store.places.count) * pitch)
    }

    private func allWorking(at date: Date) -> Bool {
        store.showWorkHours && store.places.count > 1
            && store.places.allSatisfy { store.isWorking($0, at: date) }
    }

    /// The only darkening on a row's photo: black easing slowly (smoothstep, so no edge or band)
    /// from 45% at the card's leading edge to nothing where the label ends. The clear gap and the
    /// tiles' side are the photo as it is; the label's words carry their own halo and chips.
    private func scrim(textEnd: CGFloat, cardWidth: CGFloat) -> some View {
        let end: CGFloat = min(max(textEnd / max(cardWidth, 1), 0.01), 1)
        let steps = 10
        let stops: [Gradient.Stop] = (0...steps).map { (step: Int) -> Gradient.Stop in
            let t = Double(step) / Double(steps)
            let ease = t * t * (3 - 2 * t)
            return Gradient.Stop(color: Palette.scrim.opacity(0.45 * (1 - ease)), location: end * CGFloat(t))
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func nowOutline(tile: CGFloat, tileHeight: CGFloat, tileBottom: CGFloat) -> some View {
        let inset = ui.lensInset(tile: tile)
        let shape = RoundedRectangle(cornerRadius: ui.lensRadius(tile: tile), style: .continuous)
        let top = overlapRowHeight + rowSpacing + (rowHeight - tileBottom - tileHeight)
            - tileHeight * (ui.nowScale - 1) / 2 - inset
        return ZStack {
            shape.stroke(Color.black.opacity(0.6), lineWidth: ui.lensCore + 2 * ui.lensEdge)
            shape.stroke(Color.white.opacity(0.85), lineWidth: ui.lensCore)
        }
        .frame(
            width: tile * ui.nowScale + 2 * inset,
            height: CGFloat(max(store.places.count - 1, 0)) * pitch + tileHeight * ui.nowScale + 2 * inset
        )
        .padding(.top, top)
        .allowsHitTesting(false)
    }
}

/// A city's label on its card: the time there (large), the city, then its zone or day shift and
/// whether it is at work. Tall rows take three lines; short rows fold the same into two.
private struct PlaceLabel: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    let place: Place
    let moment: Date
    let editing: Bool
    let pitch: CGFloat
    let rowHeight: CGFloat

    @State private var dragStartIndex: Int?
    @State private var handleHovered = false

    private var tall: Bool { rowHeight >= ui.threeLineRow }

    /// Black behind the small white text (zone, day shift): at 55% white keeps 4.7:1 even on a
    /// pure white photo with no other darkening.
    fileprivate static let chipBacking: Double = 0.55

    var body: some View {
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        HStack(spacing: ui.s) {
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(ui.font(13, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: max(24, ui.pt(20)), height: ui.pt(32))
                    .background(Circle().fill(Palette.scrim.opacity(0.45)))
                    .contentShape(Rectangle())
                    .help("Drag to reorder")
                    .gesture(reorderGesture)
                    .accessibilityElement()
                    .accessibilityLabel("Reorder \(place.name)")
                    .testID("handle-\(place.name)")
                    .onHover { inside in
                        guard inside != handleHovered else { return }
                        handleHovered = inside
                        if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
                    // Removed or Edit turned off while hovered: put the cursor back.
                    .onDisappear { if handleHovered { handleHovered = false; NSCursor.pop() } }
            }
            VStack(alignment: .leading, spacing: 1) {
                if tall {
                    timeText(digits: 22)
                    nameLine(font: ui.body)
                    metaLine(shift: shift)
                } else {
                    timeAndStatus
                    nameAndZone(shift: shift)
                }
            }
            Spacer(minLength: 0)
            if editing {
                Button {
                    withAnimation(.snappy) { store.remove(place) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(ui.font(17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.destructive)
                        .frame(width: max(28, ui.pt(28)), height: max(28, ui.pt(28)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(place.name)")
                .accessibilityLabel("Remove \(place.name)")
                .testID("delete-\(place.name)")
            }
        }
        .padding(.leading, ui.pt(6))
        .padding(.bottom, ui.pt(tall ? 9 : 6))
        .contextMenu {
            Button("Show in Menu Bar") {
                store.menuBarPlaceID = place.id
                store.menuBarStyle = .cityTime
            }
            Button("Remove", role: .destructive) { store.remove(place) }
        }
    }

    // MARK: Lines

    /// The time there: large digits, with AM or PM set small beside them.
    private func timeText(digits size: CGFloat) -> some View {
        let clock = WidgetClockView.clock(moment, zone: place.timeZone, use24h: store.use24h)
        var text = Text(clock.0)
            .font(ui.font(size, .semibold))
            .tracking(-0.4)
        if let suffix = clock.1 {
            text = text + Text("\u{2009}" + suffix).font(ui.font(11, .semibold))
        }
        return text
            .monospacedDigit()
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .photoHalo()
    }

    private func nameLine(font: Font) -> some View {
        HStack(spacing: ui.pt(4)) {
            Text(place.name)
                .font(font)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .photoHalo()
            if store.isHere(place) {
                Image(systemName: "location.fill")
                    .font(ui.font(11, .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .photoHalo()
                    .accessibilityLabel("My Location")
            }
        }
        .help(store.isHere(place) ? "\(place.name) · My Location\(store.hereCity.map { $0 != place.name ? " (\($0))" : "" } ?? "")" : place.name)
    }

    /// "+1 d" when the city is on another day than you, else its UTC offset (hidden in Edit,
    /// where the handle and delete button need the room).
    @ViewBuilder
    private func zoneOrShift(_ shift: Int) -> some View {
        if shift != 0 {
            dayBadge(shift)
        } else if !editing {
            // Small text on a bright photo: white on its own dark chip, like the status pill.
            Text(place.offsetLabel(at: moment))
                .font(ui.font(11, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ui.pt(7))
                .frame(height: max(16, ui.pt(16)))
                .background(Capsule().fill(Palette.scrim.opacity(PlaceLabel.chipBacking)))
        }
    }

    private func dayBadge(_ shift: Int) -> some View {
        Text(shift > 0 ? "+\(shift) d" : "−\(-shift) d")
            .font(ui.font(11, .semibold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ui.pt(7))
            .frame(height: max(16, ui.pt(16)))
            .background(Capsule().fill(Palette.scrim.opacity(PlaceLabel.chipBacking)))
    }

    /// Working, Off hours, Weekend, Day off, or the holiday's name; nil when working hours aren't shown.
    private var status: (title: String, color: Color)? {
        guard store.showWorkHours else { return nil }
        if store.isWorking(place, at: moment) { return ("Working", Palette.now) }
        let title = WorkWeek.offLabel(place, at: moment, start: store.workStart, end: store.workEnd) ?? "Off hours"
        switch title {
        case "Off hours": return (title, Palette.offHours)
        case "Weekend", "Day off": return (title, Palette.midnight)
        default: return (title, Palette.holiday)
        }
    }

    /// Third line of a tall row. A long holiday name drops the zone before it would be cut short.
    @ViewBuilder
    private func metaLine(shift: Int) -> some View {
        if let status {
            let pill = StatusPill(title: status.title, color: status.color)
            if editing {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ui.pt(6)) { zoneOrShift(shift); pill }
                    pill
                    Color.clear.frame(width: 1, height: max(16, ui.pt(16)))
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ui.pt(6)) { zoneOrShift(shift); pill }
                    pill
                }
            }
        } else {
            zoneOrShift(shift)
        }
    }

    /// First line of a short row: the time, and the status beside it when there is room.
    @ViewBuilder
    private var timeAndStatus: some View {
        if let status {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ui.pt(6)) {
                    timeText(digits: 20).fixedSize()
                    StatusPill(title: status.title, color: status.color)
                }
                if editing {
                    timeText(digits: 20)
                } else {
                    // Too long to fit (a holiday name): the pill shortens, it never vanishes.
                    HStack(spacing: ui.pt(6)) {
                        timeText(digits: 20).fixedSize()
                        StatusPill(title: status.title, color: status.color)
                    }
                }
            }
        } else {
            timeText(digits: 20)
        }
    }

    /// Second line of a short row: the city, then its day shift or (dropped first) its zone.
    @ViewBuilder
    private func nameAndZone(shift: Int) -> some View {
        let name = nameLine(font: ui.font(14, .semibold))
        if shift != 0 {
            HStack(spacing: ui.pt(6)) { name; dayBadge(shift) }
        } else if editing {
            name
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ui.pt(6)) { name; zoneOrShift(shift) }
                name
            }
        }
    }

    /// Live drag-to-reorder: rows swap as the handle crosses each row boundary.
    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard let current = store.places.firstIndex(where: { $0.id == place.id }) else { return }
                let start = dragStartIndex ?? current
                if dragStartIndex == nil { dragStartIndex = current }
                let target = min(max(start + Int((value.translation.height / pitch).rounded()), 0), store.places.count - 1)
                if target != current {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.move(from: IndexSet(integer: current), to: target > current ? target + 1 : target)
                    }
                }
            }
            .onEnded { _ in dragStartIndex = nil }
    }
}

/// Whether a city is at work, in a word, in that state's colour on its own dark plate (so it
/// reads on any photo).
private struct StatusPill: View {
    @Environment(\.metrics) private var ui
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(ui.font(11, .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, ui.pt(7))
            .frame(height: max(16, ui.pt(16)))
            // The photo behind is hardly darkened now, so the plate is deeper than the chips':
            // the state's colour has less contrast to spare than white.
            .background(Capsule().fill(Palette.scrim.opacity(0.7)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .accessibilityLabel(title)
    }
}

/// One hour in one city: an opaque tile in that hour's sky colour, inside its (taller) cell. The
/// selected hour's tile is drawn larger, overflowing its cell evenly on every side. Every tile reads
/// the same way (the hour, with AM or PM under it on a 12-hour clock), midnight and noon included;
/// where a new day starts, its weekday is a small gold tag (`DayTag`) above the tile.
private struct HourCell: View {
    @Environment(\.metrics) private var ui
    let date: Date
    let zone: TimeZone
    let use24h: Bool
    /// Outside working hours there (only when working hours are highlighted).
    let dimmed: Bool
    /// Working hours are highlighted, so working tiles keep a readable blue.
    let highlights: Bool
    let isCenter: Bool
    /// The top row: the Now outline's top line passes just above its selected tile.
    let firstRow: Bool
    let width: CGFloat
    let tileHeight: CGFloat
    let tileBottom: CGFloat
    /// Room in the row above a tile of the usual size.
    let tileTop: CGFloat
    var hovered = false

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let h = Double(hour) + Double(minute) / 60
        // A new day starts in this cell (usually 00:00, but some DST changes skip midnight).
        let newDay = !calendar.isDate(date, inSameDayAs: date.addingTimeInterval(-3600))
        let k: CGFloat = isCenter ? ui.nowScale : 1
        // Always fully opaque, so the photo never shows through behind the numerals.
        let fill: Color = dimmed ? DayColor.offHoursFill(at: h)
            : (highlights ? DayColor.workingFill(at: h) : DayColor.style(at: h).fill)
        // The darkest tiles get a hairline so they still read as tiles on a night photo.
        let edged = dimmed || hour < 6 || hour >= 21
        let shape = RoundedRectangle(cornerRadius: ui.tileRadius * k, style: .continuous)
        // Under the hour: AM or PM on a 12-hour clock, at midnight and noon as at any other hour.
        let caption: String? = use24h ? nil : (hour < 12 ? "AM" : "PM")
        // The new day's weekday tag, from this tile's top. Where a short row tucks it into the
        // tile's top edge and it would reach the digits, the label moves down just enough to
        // stay clear of it (type sizes as `ui.font`; 1.2 and 0.24 are the line and the space
        // over the digits, per point of type).
        let tag = tagPlacement(scale: k)
        let digitPoints = max(11, ui.pt(isCenter ? 19 : 17))
        let captionPoints: CGFloat = caption == nil ? 0 : max(11, ui.pt(11))
        let slack: CGFloat = (tileHeight * k - 1.2 * (digitPoints + captionPoints)) / 2
        let reach: CGFloat = tag.top + tag.height + 1 - (slack + 0.24 * digitPoints)
        let nudge: CGFloat = newDay ? max(0, min(reach, slack)) : 0

        return Color.clear
            .frame(width: width, height: tileHeight)
            .overlay {
                VStack(spacing: 0) {
                    hourText(hour: hour, minute: minute)
                        .font(isCenter ? ui.cellNow : ui.cell)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let caption {
                        Text(caption)
                            .font(ui.font(11, .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 2)
                .padding(.top, 2 * nudge)
                .frame(width: width * k, height: tileHeight * k)
                .background(shape.fill(fill))
                .overlay {
                    if hovered {
                        shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    } else if edged {
                        shape.strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                    }
                }
                .overlay(alignment: .top) {
                    // A new day starts here: its weekday, centred over the tile's top. Never
                    // wider than a tile of the usual size, so beside the selected tile it sits
                    // between the Now outline's vertical lines.
                    if newDay {
                        DayTag(weekday: TimeMath.weekday(date, in: zone), tileWidth: width, height: tag.height)
                            .offset(y: tag.top)
                    }
                }
            }
            .padding(.bottom, tileBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Where the weekday tag sits: its top edge from this tile's top (negative is above the tile)
    /// and its height. Above the tile with 3 pt between them when the row has the room; in a
    /// shorter row it is 2 pt less tall and starts at the row's top, so it only laps over the tile's
    /// top edge and is never cut off by the card. Over the top row's selected tile runs the Now
    /// outline's top line: there the tag clears that line by 2 pt, or sits just inside the tile.
    private func tagPlacement(scale k: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let full = DayTag.fullHeight(ui)
        let short = full - 2
        let above = max(0, tileTop - tileHeight * (k - 1) / 2)
        if isCenter && firstRow {
            let line = ui.lensInset(tile: width) + ui.lensCore / 2 + ui.lensEdge + 2
            if above >= full + line { return (-(full + line), full) }
            if above >= short + line { return (-(short + line), short) }
            return (1, short)
        }
        if above >= full + 3 { return (-(full + 3), full) }
        return (-min(above, short + 3), short)
    }

    /// "09" or "9", with half-hour minutes set small after it.
    private func hourText(hour: Int, minute: Int) -> Text {
        let main = use24h ? String(format: "%02d", hour) : "\(hour % 12 == 0 ? 12 : hour % 12)"
        var text = Text(main)
        if minute != 0 {
            text = text + Text(":\(String(format: "%02d", minute))").font(ui.font(11, .medium))
        }
        return text
    }
}

/// The new day's weekday ("WED") over the tile where the day starts: gold on a dark pill, the same
/// on every platform. Type follows the interface size (never under 11 pt).
private struct DayTag: View {
    @Environment(\.metrics) private var ui
    let weekday: String
    /// The tag is never wider than this.
    let tileWidth: CGFloat
    let height: CGFloat

    static func fullHeight(_ ui: Metrics) -> CGFloat { max(15, ui.pt(15)) }

    /// 5 pt each side of the word, or less (never under 3) so the tag is no wider than its tile.
    private var padding: CGFloat {
        let points = max(11, ui.pt(11))
        let inter: NSFont? = ui.family == .inter ? NSFont(name: "Inter-SemiBold", size: points) : nil
        let font: NSFont = inter ?? NSFont.systemFont(ofSize: points, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: CGFloat(0.3)]
        let word = (weekday.uppercased() as NSString).size(withAttributes: attributes).width
        return min(5, max(3, ((tileWidth - word) / 2).rounded(.down)))
    }

    var body: some View {
        Text(weekday.uppercased())
            .font(ui.font(11, .semibold))
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Palette.midnight)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .frame(maxWidth: tileWidth)
            .allowsHitTesting(false)
    }
}

private struct ColumnHeader: View {
    @Environment(\.metrics) private var ui
    let hoursFromNow: Int
    let isCenter: Bool
    let isOverlap: Bool

    private var label: String {
        hoursFromNow == 0 ? "Now" : (hoursFromNow > 0 ? "+\(hoursFromNow) hr" : "−\(-hoursFromNow) hr")
    }

    var body: some View {
        VStack(spacing: ui.pt(3)) {
            Text(label)
                .font(ui.font(11, hoursFromNow == 0 || isCenter ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(hoursFromNow == 0 ? Palette.cream : (isCenter ? Palette.textPrimary : Palette.textMuted))
                .lineLimit(1)
            OverlapMark(isOverlap: isOverlap)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .help(hoursFromNow == 0 ? "The current hour" : "\(abs(hoursFromNow)) hour\(abs(hoursFromNow) == 1 ? "" : "s") \(hoursFromNow > 0 ? "from now" : "ago")")
    }
}

private struct OverlapMark: View {
    @Environment(\.metrics) private var ui
    let isOverlap: Bool

    var body: some View {
        Capsule()
            .fill(isOverlap ? Palette.cream : .clear)
            .frame(width: ui.pt(16), height: 3)
            .help(isOverlap ? "Everyone is in working hours" : "")
    }
}

// MARK: - Text on a photo

private extension View {
    /// A soft dark halo, so white words read on a bright photo that is hardly darkened.
    func photoHalo() -> some View {
        self
            .shadow(color: .black.opacity(0.75), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.55), radius: 5)
            .shadow(color: .black.opacity(0.35), radius: 11)
    }
}

// MARK: - Scroll wheel / trackpad time travel

extension View {
    /// Calls `action` with -1 / +1 hour steps as the user scrolls horizontally (or vertically).
    func onScrollWheel(_ action: @escaping (Int) -> Void) -> some View {
        background(ScrollWheelCatcher(action: action))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    let action: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                // Horizontal swipes (or Shift + wheel) travel in time; vertical scrolling
                // is left for the panel so it can scroll at large sizes.
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                let delta = -event.scrollingDeltaX
                self.accumulated += event.hasPreciseScrollingDeltas ? delta : delta * 12
                if abs(self.accumulated) >= 32 {
                    let steps = Int(self.accumulated / 32)
                    self.accumulated -= CGFloat(steps) * 32
                    self.action?(steps)
                }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
