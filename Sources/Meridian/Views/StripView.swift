import SwiftUI
import AppKit

/// Day-and-night ribbons, one row per city. Every column is the same instant everywhere,
/// so "now" (or any travelled-to hour) reads as one straight line down the centre.
struct StripView: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    var cellWidth: CGFloat = 52
    var rowHeight: CGFloat = 48
    var labelWidth: CGFloat = 176
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
            let stripWidth = max(cellWidth * 5, geo.size.width - labelWidth)
            let half = Int(stripWidth / cellWidth / 2) + 2
            let total = Double(store.offsetHours) - Double(drag / cellWidth)
            let base = Int(total.rounded())
            let frac = total - Double(base)
            let anchor = TimeMath.hourAnchor(store.now)
            let moment = base == 0 ? store.now : anchor.addingTimeInterval(Double(base) * 3600)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    Color.clear.frame(height: overlapRowHeight)
                    ForEach(store.places) { place in
                        PlaceLabel(place: place, moment: moment, editing: editing, pitch: pitch)
                            .frame(width: labelWidth - ui.l, height: rowHeight, alignment: .leading)
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
                                .frame(width: cellWidth - cellGap, height: overlapRowHeight)
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
                                        dimmed: store.showWorkHours && !store.isWorkHour(hour(date, place.timeZone)),
                                        isCenter: index == base,
                                        hovered: hoverIndex == index && index != base
                                    )
                                    .frame(width: cellWidth - cellGap, height: rowHeight)
                                    .contentShape(Rectangle())
                                    .onHover { inside in
                                        if inside { hoverIndex = index } else if hoverIndex == index { hoverIndex = nil }
                                    }
                                    .onTapGesture { store.travel(index - store.offsetHours) }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .testID("hour-\(place.name)-\(index)")
                                }
                            }
                        }
                    }
                    .offset(x: -CGFloat(frac) * cellWidth)
                    .frame(width: stripWidth)

                    // The "now" lens.
                    RoundedRectangle(cornerRadius: ui.lensRadius, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: ui.lensRadius, style: .continuous)
                                .strokeBorder(.white, lineWidth: ui.lensStroke)
                        )
                        .frame(
                            width: cellWidth - cellGap + 2 * ui.lensOutset,
                            height: CGFloat(store.places.count) * pitch - rowSpacing + 2 * ui.lensOutset
                        )
                        .padding(.top, overlapRowHeight + rowSpacing - ui.lensOutset)
                        .allowsHitTesting(false)
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
            }
        }
        .frame(height: overlapRowHeight + CGFloat(store.places.count) * pitch + ui.lensOutset)
    }

    private func hour(_ date: Date, _ zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: date)
    }

    private func allWorking(at date: Date) -> Bool {
        store.showWorkHours && store.places.count > 1
            && store.places.allSatisfy { store.isWorkHour(hour(date, $0.timeZone)) }
    }
}

private struct PlaceLabel: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    let place: Place
    let moment: Date
    let editing: Bool
    let pitch: CGFloat

    @State private var dragStartIndex: Int?
    @State private var handleHovered = false

    var body: some View {
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        HStack(spacing: ui.s) {
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(ui.font(13, .medium))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: max(24, ui.pt(20)), height: ui.pt(32))
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
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(ui.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(place.name)
                HStack(spacing: ui.pt(6)) {
                    Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                    if shift != 0 {
                        Text(shift > 0 ? "+\(shift) day" : "−\(-shift) day")
                            .font(ui.font(11, .medium))
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, ui.pt(7))
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.borderStrong))
                    } else if !editing {
                        // Hidden in Edit, where the handle and delete button need the room.
                        Text(place.offsetLabel(at: moment))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                .font(ui.meta)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if editing {
                Button {
                    withAnimation(.snappy) { store.remove(place) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(ui.font(17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.crimson)
                        .frame(width: max(28, ui.pt(28)), height: max(28, ui.pt(28)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(place.name)")
                .accessibilityLabel("Remove \(place.name)")
                .testID("delete-\(place.name)")
            }
        }
        .contextMenu {
            Button("Show in Menu Bar") {
                store.menuBarPlaceID = place.id
                store.menuBarStyle = .cityTime
            }
            Button("Remove", role: .destructive) { store.remove(place) }
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

private struct HourCell: View {
    @Environment(\.metrics) private var ui
    let date: Date
    let zone: TimeZone
    let use24h: Bool
    let dimmed: Bool
    let isCenter: Bool
    var hovered = false

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        // A new day starts in this cell (usually 00:00, but some DST changes skip midnight).
        let newDay = !calendar.isDate(date, inSameDayAs: date.addingTimeInterval(-3600))

        return VStack(spacing: 1) {
            hourText(hour: hour, minute: minute)
                .font(isCenter ? ui.cellNow : ui.cell)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if newDay {
                Text(TimeMath.weekday(date, in: zone))
                    .font(ui.font(10, .medium))
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
        }
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: ui.tileRadius, style: .continuous)
                .fill(style.fill.opacity(dimmed ? 0.72 : 1))
        )
        .overlay(alignment: .leading) {
            // Midnight divider: a new day starts here.
            if newDay {
                // Midnight marker: 2pt crimson line centred in the gutter before the cell.
                Capsule().fill(Palette.crimson).frame(width: 2).padding(.vertical, ui.s).offset(x: -(ui.gutter / 2 + 1))
            }
        }
    }

    private func hourText(hour: Int, minute: Int) -> Text {
        let main: String
        var suffix = ""
        if use24h {
            main = String(format: "%02d", hour)
        } else {
            main = "\(hour % 12 == 0 ? 12 : hour % 12)"
            suffix = hour < 12 ? "am" : "pm"
        }
        var text = Text(main)
        if minute != 0 {
            text = text + Text(":\(String(format: "%02d", minute))").font(ui.font(11, .medium))
            // "12:30a": the short suffix keeps half-hour zones on one line.
            if !suffix.isEmpty { suffix = String(suffix.prefix(1)) }
        }
        if !suffix.isEmpty { text = text + Text(suffix).font(ui.font(10, .medium)) }
        return text
    }
}

private struct ColumnHeader: View {
    @Environment(\.metrics) private var ui
    let hoursFromNow: Int
    let isCenter: Bool
    let isOverlap: Bool

    private var label: String {
        hoursFromNow == 0 ? "Now" : (hoursFromNow > 0 ? "+\(hoursFromNow) h" : "−\(-hoursFromNow) h")
    }

    var body: some View {
        VStack(spacing: ui.pt(3)) {
            Text(label)
                .font(ui.font(11, hoursFromNow == 0 || isCenter ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(hoursFromNow == 0 ? Palette.cream : (isCenter ? Palette.textPrimary : Palette.textMuted))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
