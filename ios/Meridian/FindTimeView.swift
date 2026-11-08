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
    private var calendar: Calendar { Calendar.current }

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
                    PillChip(title: i == 0 ? "Today" : i == 1 ? "Tomorrow" : Self.dayChip.string(from: date),
                             isOn: calendar.isDate(date, inSameDayAs: day)) {
                        day = date
                    }
                }
            }
            .padding(.horizontal, Card.margin)
        }
        // Runs to the screen's edges, so a cut-off chip reads as "scroll for more".
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
                }
                // To the card's edges.
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
                    .font(.system(size: 15)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            VStack(spacing: 0) {
                ForEach(shown, id: \.offset) { index, run in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.2)) }
                    Button { slot = run[0] } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(range(run[0].start, run.last!.end))
                                    .font(.system(size: 20)).monospacedDigit().foregroundStyle(.white)
                                Text(run.count == 1 ? "Your time" : "Your time · start any time from \(time(run[0].start)) to \(time(run.last!.start))")
                                    .font(.system(size: 13)).foregroundStyle(Color.white.opacity(Theme.Op.sub))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
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
        let run = bestRun(in: hourly)
        return VStack(alignment: .leading, spacing: 10) {
            CardCaption("Every hour", "tablecells")
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Text("You").frame(width: 62, alignment: .leading)
                    ForEach(people) { p in Text(Self.tag(p)).frame(maxWidth: .infinity) }
                    Text("").frame(width: 30)
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
                VStack(spacing: 2) {
                    ForEach(hourly) { s in
                        Button { slot = s } label: {
                            HStack(spacing: 2) {
                                Text(Self.hourLabel(s.start, use24h: store.use24h))
                                    .font(.system(size: 13)).monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(s.working == people.count && !people.isEmpty ? 1 : Theme.Op.caption))
                                    .frame(width: 62, alignment: .leading)
                                ForEach(Array(s.states.enumerated()), id: \.offset) { _, state in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(state.color)
                                        .frame(maxWidth: .infinity)
                                }
                                Text("\(s.working)/\(people.count)")
                                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.white.opacity(0.5))
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .frame(height: Self.cell)
                            .opacity(s.end <= store.now ? 0.35 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Self.hourLabel(s.start, use24h: store.use24h)), \(s.working) of \(people.count) working")
                    }
                }
                // The best hours, outlined (rows are a fixed pitch, so its place is exact).
                .overlay(alignment: .top) {
                    if let run {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 1.5)
                            .frame(height: CGFloat(run.count) * Self.cell + CGFloat(run.count - 1) * 2 + 4)
                            .padding(.horizontal, -2)
                            .offset(y: CGFloat(run.lowerBound) * (Self.cell + 2) - 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Slot.State.working.color, "Working")
                legend(Slot.State.off.color, "Off")
                legend(Slot.State.night.color, "Night")
            }
            .padding(.top, 2)
        }
        .glassCard()
    }

    private static let cell: CGFloat = 22

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

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 11, height: 11)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
        }
    }

    private func time(_ date: Date) -> String { TimeMath.time(date, in: .current, use24h: store.use24h) }
    private func range(_ a: Date, _ b: Date) -> String { "\(time(a))–\(time(b))" }

    static func quarter(_ date: Date) -> Date { Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900) }

    static func lengthLabel(_ minutes: Int) -> String { minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60)½ hr" }

    static func tag(_ place: Place) -> String { String(place.title.filter(\.isLetter).prefix(3)).uppercased() }

    static func hourLabel(_ date: Date, use24h: Bool) -> String {
        let h = Calendar.current.component(.hour, from: date)
        return use24h ? String(format: "%02d:00", h) : "\(h % 12 == 0 ? 12 : h % 12)\u{2009}\(h < 12 ? "AM" : "PM")"
    }

    private static let dayChip: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d"
        return f
    }()
}

/// One possible meeting time and how it is for each person in it.
struct Slot: Identifiable {
    enum State {
        case working, off, night
        var color: Color {
            switch self {
            case .working: return Color.white.opacity(0.85)
            case .off: return Color.white.opacity(0.3)
            case .night: return Color.white.opacity(0.08)
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
                        Text("\(TimeMath.time(start, in: .current, use24h: store.use24h))–\(TimeMath.time(end, in: .current, use24h: store.use24h))")
                            .font(.system(size: 44, weight: .thin)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(TimeMath.fullDay(start, in: .current)) · your time · \(FindTimeView.lengthLabel(length))")
                            .font(.system(size: 15)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
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
                                Text(place.title).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                                Text(status(place)).font(.system(size: 13)).foregroundStyle(Color.white.opacity(Theme.Op.sub))
                            }
                            .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(TimeMath.time(start, in: place.timeZone, use24h: store.use24h))–\(TimeMath.time(end, in: place.timeZone, use24h: store.use24h))")
                                .font(.system(size: 15)).monospacedDigit().foregroundStyle(.white).fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .meridianSection()
                Section {
                    Button { addingEvent = true } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                    ShareLink(item: invite, subject: Text("Meeting, \(TimeMath.fullDay(start, in: .current))")) {
                        Label("Share Invite…", systemImage: "square.and.arrow.up")
                    }
                    Button { UIPasteboard.general.string = invite } label: { Label("Copy Invite", systemImage: "doc.on.doc") }
                    Button {
                        store.jump(to: start)
                        dismiss()
                    } label: { Label("Go to This Time", systemImage: "clock.arrow.circlepath") }
                }
                .font(.system(size: 17))
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
