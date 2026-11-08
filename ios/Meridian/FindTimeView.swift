import EventKit
import EventKitUI
import SwiftUI

/// Find a Time: pick a day, a length and who's in it, and see when everyone is working (each
/// city's own working days and hours, its public holidays, and night), with the best times first.
/// Tap a time to add it to your calendar, share an invite with every city's time, or go there.
struct FindTimeView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var length = 60
    @State private var chosen: Set<UUID> = []
    @State private var slot: Slot?

    private static let lengths = [30, 60, 90, 120]
    /// Your clock (the device's time zone; San Francisco's in screenshot mode, as on the ruler).
    private var calendar: Calendar { store.homeCalendar }

    /// The cards in the meeting, one per time zone and city (a person counts as their own).
    private var people: [Place] { store.places.filter { chosen.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    days
                    lengthPicker
                    who
                    best
                    grid
                }
                .padding(.horizontal, Card.margin)
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .navigationTitle("Find a Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $slot) { slot in
                SlotView(slot: slot, length: length, places: people).environmentObject(store)
            }
            .onAppear {
                // The group showing on the list (every city when it has none yet).
                if chosen.isEmpty {
                    let visible = store.visiblePlaces
                    chosen = Set((visible.isEmpty ? store.places : visible).map(\.id))
                }
                // Today on the app's clock; after work, tomorrow.
                day = calendar.startOfDay(for: store.now)
                if calendar.component(.hour, from: store.now) >= 17 { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: Choices

    private var days: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<14, id: \.self) { i in
                    let date = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: store.now)) ?? store.now
                    PillChip(title: i == 0 ? "Today" : i == 1 ? "Tomorrow" : chipDay(date),
                             isOn: calendar.isDate(date, inSameDayAs: day)) {
                        day = date
                    }
                }
            }
            .padding(.horizontal, Card.margin)
            .padding(.trailing, 24 - Card.margin)
        }
        // Runs to the screen's edges, and a chip cut there fades out: "scroll for more", never "Sat 1".
        .chipRowFade()
        .padding(.horizontal, -Card.margin)
        .padding(.top, 4)
    }

    private var lengthPicker: some View {
        Picker("Length", selection: $length) {
            ForEach(Self.lengths, id: \.self) { minutes in
                Text(Self.lengthLabel(minutes)).tag(minutes)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
    }

    /// Who's in it: every card as a chip, and the groups as quick picks.
    private var who: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardCaption("Who", "person.2")
            // Groups with cities in them, in the chips' order.
            let groups = store.chipGroups.filter { store.groupCount($0) > 0 }
            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PillChip(title: "Everyone", isOn: chosen == Set(store.places.map(\.id))) { chosen = Set(store.places.map(\.id)) }
                        ForEach(groups, id: \.self) { group in
                            let ids = Set(store.places.filter { store.groups(of: $0).contains(group) }.map(\.id))
                            PillChip(title: group, isOn: chosen == ids) { chosen = ids }
                        }
                    }
                    .padding(.horizontal, Card.padding)
                    .padding(.trailing, 24 - Card.padding)
                }
                // To the card's edges; a group chip cut there fades out ("As" read as a word).
                .chipRowFade()
                .padding(.horizontal, -Card.padding)
            }
            // The chips' 44 pt touch areas overlap a little, so the visible rows sit 8 pt apart.
            FlowLayout(spacing: 8, lineSpacing: -4) {
                ForEach(store.places) { place in
                    let on = chosen.contains(place.id)
                    PillChip(title: place.title, systemImage: on ? "checkmark" : "plus", isOn: on) {
                        if on { chosen.remove(place.id) } else { chosen.insert(place.id) }
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: Answers

    /// Every half-hour start on your day, scored by how many are working for the whole meeting.
    private var slots: [Slot] {
        (0..<48).compactMap { i in
            guard let start = calendar.date(byAdding: .minute, value: i * 30, to: day) else { return nil }
            let end = start.addingTimeInterval(Double(length) * 60)
            let states = people.map { Slot.state(for: $0, from: start, to: end, store: store) }
            return Slot(start: start, end: end, states: states)
        }
    }

    /// The most people working at any time still to come on the day.
    private func mostWorking(_ all: [Slot]) -> Int {
        all.filter { $0.start >= Self.quarter(store.now) }.map(\.working).max() ?? 0
    }

    /// The best times: the longest runs where the most people are working, soonest first.
    private var best: some View {
        let all = slots.filter { $0.start >= Self.quarter(store.now) }
        let top = mostWorking(all)
        var runs: [[Slot]] = []
        for s in all where s.working == top && top > 0 {
            if let last = runs.last?.last, s.start.timeIntervalSince(last.start) == 1800 { runs[runs.count - 1].append(s) } else { runs.append([s]) }
        }
        let shown = Array(runs.prefix(3).enumerated())
        return VStack(alignment: .leading, spacing: 10) {
            CardCaption(people.isEmpty ? "Choose who's in it" : top == people.count ? "Everyone's working" : top == 0 ? "No one's working then" : "Best: \(top) of \(people.count) working",
                        "checkmark.circle")
            if runs.isEmpty {
                Text(people.isEmpty ? "Tap the cities and people above." : "Try another day, or fewer people.")
                    .font(.subheadline).foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            VStack(spacing: 0) {
                ForEach(shown, id: \.offset) { index, run in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.2)) }
                    Button { slot = run[0] } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(range(run[0].start, run.last!.end))
                                    .font(.title3).monospacedDigit().foregroundStyle(.white)
                                Text(run.count == 1 ? "Your time" : "Your time · start any time from \(time(run[0].start)) to \(time(run.last!.start))")
                                    .font(.footnote).foregroundStyle(Color.white.opacity(Theme.Op.sub))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    /// The day hour by hour (your time): a cell per person, bright while they're working, dim
    /// when they're off, dark at night where they are; the best run outlined.
    private var grid: some View {
        let hourly = slots.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        return VStack(alignment: .leading, spacing: 10) {
            // The key beside the title, where the eye starts (it sat below the grid, under the fold).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    CardCaption("Every hour", "tablecells")
                    Spacer(minLength: 4)
                    gridKey
                }
                VStack(alignment: .leading, spacing: 6) {
                    CardCaption("Every hour", "tablecells")
                    // Under the title the key wraps: one row if it fits, else one legend per line.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { legends }
                        VStack(alignment: .leading, spacing: 4) { legends }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            // Rows are a fixed pitch (the best run's outline depends on it), so the grid grows with the
            // reader's text size up to accessibility1 (its hour and count columns widen with it).
            HourGrid(hourly: hourly, people: people, run: bestRun(in: hourly), now: store.now, use24h: store.use24h,
                     calendar: calendar) { slot = $0 }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .glassCard()
    }

    /// Working, Off and Night, each as its cell looks in the grid, on one line beside the title.
    /// Capped at accessibility1, as the grid it explains.
    private var gridKey: some View {
        HStack(spacing: 10) { legends }
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder private var legends: some View {
        legend(.working, "Working")
        legend(.off, "Off")
        legend(.night, "Night")
    }

    /// The first run of hours, still to come, where the most people are working.
    private func bestRun(in hourly: [Slot]) -> Range<Int>? {
        guard !people.isEmpty else { return nil }
        let top = mostWorking(hourly)
        guard top > 0 else { return nil }
        let soonest = Self.quarter(store.now)
        guard let first = hourly.firstIndex(where: { $0.start >= soonest && $0.working == top }) else { return nil }
        var end = first + 1
        while end < hourly.count, hourly[end].working == top { end += 1 }
        return first..<end
    }

    private func legend(_ state: Slot.State, _ text: String) -> some View {
        HStack(spacing: 4) {
            // A small cell in the grid cells' proportions (wide, gently rounded).
            SlotCell(state: state, past: false, glyph: 8, radius: 3)
                .frame(width: 18, height: 13)
            Text(text).font(.footnote).foregroundStyle(Color.white.opacity(Theme.Op.sub))
        }
        .accessibilityElement(children: .combine)
    }

    private func time(_ date: Date) -> String { TimeMath.time(date, in: store.home, use24h: store.use24h) }
    private func range(_ a: Date, _ b: Date) -> String { "\(time(a))–\(time(b))" }

    static func quarter(_ date: Date) -> Date { Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900) }

    static func lengthLabel(_ minutes: Int) -> String { minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60)½ hr" }

    /// The column header: the Lock Screen widgets' short name for a city ("SF", "NY", "LON"), so the
    /// same city reads the same everywhere; a person's first three letters.
    static func tag(_ place: Place) -> String {
        if place.person == nil {
            let words = place.name.split(whereSeparator: { !$0.isLetter }).filter { !$0.isEmpty }
            if words.count > 1 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
        }
        return String(place.title.filter(\.isLetter).prefix(3)).uppercased()
    }

    static func hourLabel(_ date: Date, use24h: Bool, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        return use24h ? String(format: "%02d:00", h) : "\(h % 12 == 0 ? 12 : h % 12)\u{2009}\(h < 12 ? "AM" : "PM")"
    }

    /// "Tue 9", on your clock (as the day chips are counted).
    private func chipDay(_ date: Date) -> String {
        Self.dayChip.timeZone = store.home
        return Self.dayChip.string(from: date)
    }

    private static let dayChip: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d"
        return f
    }()
}

/// Find a Time's hour-by-hour grid, a view of its own so its row pitch and columns follow the text
/// size it is capped at. Past hours dim only their cells: their hour and count stay readable (a
/// past hour still opens its time).
private struct HourGrid: View {
    let hourly: [Slot]
    let people: [Place]
    /// The best run of rows, outlined.
    let run: Range<Int>?
    let now: Date
    let use24h: Bool
    let calendar: Calendar
    let open: (Slot) -> Void

    @ScaledMetric(relativeTo: .footnote) private var cell: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .caption) private var countWidth: CGFloat = 32

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("You").frame(width: labelWidth, alignment: .leading)
                ForEach(people) { p in Text(FindTimeView.tag(p)).frame(maxWidth: .infinity) }
                Text("").frame(width: countWidth)
            }
            // Footnote (13 pt), not caption2 (11 pt): the column names are the grid's smallest text.
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.white.opacity(Theme.Op.sub))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            VStack(spacing: 2) {
                ForEach(hourly) { s in
                    row(s)
                }
            }
            // The best hours, outlined (rows are a fixed pitch, so its place is exact).
            .overlay(alignment: .top) {
                if let run {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .frame(height: CGFloat(run.count) * cell + CGFloat(run.count - 1) * 2 + 4)
                        .padding(.horizontal, -2)
                        .offset(y: CGFloat(run.lowerBound) * (cell + 2) - 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func row(_ s: Slot) -> some View {
        let past = s.end <= now
        let label = FindTimeView.hourLabel(s.start, use24h: use24h, calendar: calendar)
        let everyone = s.working == people.count && !people.isEmpty
        let ink: Double = everyone ? 1 : (past ? Theme.Op.caption : Theme.Op.sub)
        return Button { open(s) } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: labelWidth, alignment: .leading)
                ForEach(Array(s.states.enumerated()), id: \.offset) { _, state in
                    SlotCell(state: state, past: past)
                        .frame(maxWidth: .infinity)
                }
                Text("\(s.working)/\(people.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: countWidth, alignment: .trailing)
            }
            .frame(height: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(s.working) of \(people.count) working\(past ? ", past" : "")")
    }
}

/// One person's cell in an hour of the grid (and in its key). Working is a pale sky blue (the hour
/// tiles' hue, as bright as the old white), Off a mid grey, Night the hour tiles' night ink
/// (#0A0E1C) with a hairline edge and a small moon (white 0.75, 10.8:1 on it), so night never depends on brightness alone. On the card (~#1F1F1F):
/// working 3.4:1 against off (was 4.5), off ~4.7:1 against night (was 3.2); past hours (cells at
/// 0.9, composited on the card) ~3.2:1 working/off and ~4.1:1 off/night. The night fill alone is
/// only ~1.16:1 against the card, so the 0.75 pt edge (3.8:1 on the card) and the moon carry the
/// distinction between a night cell and the card.
private struct SlotCell: View {
    let state: Slot.State
    let past: Bool
    /// The moon's size.
    var glyph: CGFloat = 9
    /// The corner radius (the key's small swatches use less).
    var radius: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(state.color)
            .overlay {
                if state == .night {
                    ZStack {
                        shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                        Image(systemName: "moon.fill")
                            .font(.system(size: glyph, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
            // Past hours dim a little (the hour label marks past too); who was working still reads.
            .opacity(past ? 0.9 : 1)
            .accessibilityHidden(true)
    }
}

/// One possible meeting time and how it is for each person in it.
struct Slot: Identifiable {
    enum State {
        case working, off, night
        var color: Color {
            switch self {
            // #DDEAFA: L 0.81, as bright as the old white 0.85, with the hour tiles' sky-blue hue.
            case .working: return Theme.rgb(0xDDEAFA)
            case .off: return Color.white.opacity(0.42)
            // The hour tiles' night ink (#0A0E1C), so night is the same colour here as on the
            // main list and reads as a dark state (off vs night ~4.7:1, past ~4.1:1; was 3.2), not an empty slot.
            case .night: return Theme.rgb(0x0A0E1C)
            }
        }
    }

    let start: Date
    let end: Date
    let states: [State]
    var id: Date { start }
    var working: Int { states.filter { $0 == .working }.count }

    /// Working for the whole meeting; else night if the sun is down there as it starts; else off.
    @MainActor static func state(for place: Place, from start: Date, to end: Date, store: CityStore) -> State {
        if store.isWorking(place, at: start), store.isWorking(place, at: end.addingTimeInterval(-60)) { return .working }
        switch Sun.phase(place, at: start) {
        case .night?, .allNight?: return .night
        default: return .off
        }
    }
}

/// A chosen time: each person's time and how it is for them, then Add to Calendar, Share Invite
/// or Go to This Time.
private struct SlotView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    let slot: Slot
    let length: Int
    let places: [Place]
    @State private var start: Date
    @State private var addingEvent = false
    /// The chosen time, large; grows with the reader's text size (it shrinks to fit one line).
    @ScaledMetric(relativeTo: .largeTitle) private var rangeSize: CGFloat = 44

    init(slot: Slot, length: Int, places: [Place]) {
        self.slot = slot
        self.length = length
        self.places = places
        _start = State(initialValue: slot.start)
    }

    private var end: Date { start.addingTimeInterval(Double(length) * 60) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(TimeMath.time(start, in: store.home, use24h: store.use24h))–\(TimeMath.time(end, in: store.home, use24h: store.use24h))")
                            .font(.system(size: rangeSize, weight: .regular)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(TimeMath.fullDay(start, in: store.home)) · your time · \(FindTimeView.lengthLabel(length))")
                            .font(.subheadline).foregroundStyle(Color.white.opacity(Theme.Op.caption))
                    }
                    .padding(.vertical, 6)
                    Stepper("Start", onIncrement: { start = start.addingTimeInterval(900) }, onDecrement: { start = start.addingTimeInterval(-900) })
                        .foregroundStyle(.white)
                }
                .meridianSection()
                Section {
                    ForEach(places) { place in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.title).font(.body.weight(.medium)).foregroundStyle(.white)
                                Text(status(place)).font(.footnote).foregroundStyle(Color.white.opacity(Theme.Op.sub))
                            }
                            .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(TimeMath.time(start, in: place.timeZone, use24h: store.use24h))–\(TimeMath.time(end, in: place.timeZone, use24h: store.use24h))")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.white).fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .meridianSection()
                Section {
                    Button { addingEvent = true } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                    ShareLink(item: invite, subject: Text("Meeting, \(TimeMath.fullDay(start, in: store.home))")) {
                        Label("Share Invite…", systemImage: "square.and.arrow.up")
                    }
                    Button { UIPasteboard.general.string = invite } label: { Label("Copy Invite", systemImage: "doc.on.doc") }
                    Button {
                        store.jump(to: start)
                        dismiss()
                    } label: { Label("Go to This Time", systemImage: "clock.arrow.circlepath") }
                }
                .font(.body)
                .foregroundStyle(.white)
                .meridianSection()
            }
            .listStyle(.insetGrouped)
            .meridianForm()
            .navigationTitle("Meeting Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $addingEvent) {
                EventEditor(title: "Meeting", start: start, end: end, notes: invite).ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    /// "Working", "Off hours", "Thanksgiving Day", with "Wed" when it's another day there.
    private func status(_ place: Place) -> String {
        let work = store.isWorking(place, at: start) ? "Working" : (WorkWeek.offLabel(place, at: start, start: store.workStart, end: store.workEnd) ?? "Off")
        let shift = TimeMath.dayShift(start, zone: place.timeZone)
        let city = place.person != nil ? "\(place.name) · " : ""
        return city + work + (shift == 0 ? "" : " · \(TimeMath.weekday(start, in: place.timeZone))")
    }

    /// Every person's time, ready to paste into an invite.
    private var invite: String {
        var lines = ["Meeting · \(FindTimeView.lengthLabel(length))"]
        for place in places {
            let who = place.person.map { "\($0) (\(place.name))" } ?? place.name
            let day = TimeMath.fullDay(start, in: place.timeZone)
            lines.append("\(who): \(day), \(TimeMath.time(start, in: place.timeZone, use24h: store.use24h))–\(TimeMath.time(end, in: place.timeZone, use24h: store.use24h)) (\(place.offsetLabel(at: start)))")
        }
        lines.append("")
        lines.append("Times by Meridian: \(Theme.appPage.absoluteString)")
        return lines.joined(separator: "\n")
    }
}

/// Apple's event editor, filled in: the person picks the calendar and invitees and saves. Since
/// iOS 17 this needs no calendar permission (the editor runs outside the app).
struct EventEditor: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    let notes: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { done() }
    }
}

/// Chips that wrap onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Between lines; the same as `spacing` unless set.
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + (lineSpacing ?? spacing); line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + (lineSpacing ?? spacing); line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
