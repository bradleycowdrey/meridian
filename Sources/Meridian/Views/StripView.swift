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

    @State private var drag: CGFloat = 0
    @State private var hoverIndex: Int?
    private var rowSpacing: CGFloat { ui.s }
    private var cellGap: CGFloat { ui.xs }
    private var overlapRowHeight: CGFloat { ui.pt(12) }

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

                ZStack(alignment: .top) {
                    VStack(spacing: rowSpacing) {
                        HStack(spacing: cellGap) {
                            ForEach((base - half)...(base + half), id: \.self) { index in
                                OverlapMark(isOverlap: allWorking(at: anchor.addingTimeInterval(Double(index) * 3600)))
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
                                }
                            }
                        }
                    }
                    .offset(x: -CGFloat(frac) * cellWidth)
                    .frame(width: stripWidth)

                    // The "now" lens.
                    RoundedRectangle(cornerRadius: ui.pt(14), style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: ui.pt(14), style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        )
                        .frame(width: cellWidth + ui.xs, height: CGFloat(store.places.count) * pitch)
                        .padding(.top, overlapRowHeight + rowSpacing / 2)
                        .allowsHitTesting(false)
                }
                .frame(width: stripWidth)
                .clipped()
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
                        .onChanged { drag = $0.translation.width }
                        .onEnded { value in
                            let hours = Int((-value.translation.width / cellWidth).rounded())
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                drag = 0
                                store.offsetHours += hours
                            }
                        }
                )
                .onScrollWheel { delta in store.travel(delta) }
            }
        }
        .frame(height: overlapRowHeight + CGFloat(store.places.count) * pitch + rowSpacing / 2)
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

    var body: some View {
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        HStack(spacing: ui.s) {
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: ui.pt(13), weight: .medium))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: ui.pt(20), height: ui.pt(32))
                    .contentShape(Rectangle())
                    .help("Drag to reorder")
                    .gesture(reorderGesture)
                    .onHover { inside in
                        if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(ui.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: ui.pt(6)) {
                    Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                    if shift != 0 {
                        Text(shift > 0 ? "+1 day" : "−1 day")
                            .font(.system(size: ui.pt(11), weight: .medium))
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, ui.pt(7))
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.borderStrong))
                    } else {
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
                        .font(.system(size: ui.pt(17)))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.crimson)
                        .frame(width: ui.pt(28), height: ui.pt(28))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(place.name)")
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

        return VStack(spacing: 1) {
            hourText(hour: hour, minute: minute)
                .font(isCenter ? ui.cellNow : ui.cell)
                .monospacedDigit()
            if hour == 0 {
                Text(TimeMath.weekday(date, in: zone))
                    .font(.system(size: ui.pt(10), weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
        }
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: ui.pt(10), style: .continuous)
                .fill(style.fill.opacity(dimmed ? 0.72 : 1))
        )
        .overlay(alignment: .leading) {
            // Midnight divider: a new day starts here.
            if hour == 0 {
                Capsule().fill(Palette.crimson).frame(width: 2).padding(.vertical, ui.s).offset(x: -3)
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
        if minute != 0 { text = text + Text(":\(String(format: "%02d", minute))").font(.system(size: ui.pt(11), weight: .medium)) }
        if !suffix.isEmpty { text = text + Text(suffix).font(.system(size: ui.pt(10), weight: .medium)) }
        return text
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
        let text = luminance > 0.55 ? Palette.bg : Palette.textSecondary
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), text)
    }

    private static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
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
                let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
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
