import SwiftUI

/// Go to a day and time (on your clock), in quarter-hours, and see every city at that moment
/// before going there: the answer at the top, quick picks, a calendar, the time, your cities.
struct DateJumpView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var answerSize: CGFloat = 72
    /// The chosen day (any time on it) and the time on it, in quarter-hours.
    @State private var day = Date()
    @State private var hour = 9
    @State private var quarter = 0
    /// 123: type hours from now ("+3", "-1.5", "-2:30").
    @State private var typing = false
    @State private var typed = ""
    @State private var invalid = false

    /// Your clock, as on the ruler and in Find a Time (the demo's San Francisco in screenshots).
    private var calendar: Calendar { store.homeCalendar }

    /// The chosen moment: the day at hour:minute on your clock.
    private var moment: Date {
        calendar.date(bySettingHour: hour, minute: quarter * 15, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    answer
                    quickPicks
                    // The time first, right under the answer: on a 6.1-inch phone its wheel sat under
                    // the Go bar at first open. Now the whole wheel and the month's title and first
                    // weeks show before any scroll.
                    VStack(alignment: .leading, spacing: 10) {
                        CardCaption("Time", "clock")
                        timePicker
                    }
                    .glassCard()
                    VStack(alignment: .leading, spacing: 10) {
                        CardCaption("Date", "calendar")
                        // Our own month, not DatePicker(.graphical): UIKit draws its weekday row in a gray
                        // that measured 2.45:1 on the card. Here every letter and number is 6.6:1 or more.
                        MonthGrid(day: $day, calendar: calendar, today: store.now)
                    }
                    .glassCard()
                    if !store.places.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            CardCaption("In your cities", "globe")
                            cities
                        }
                        .glassCard()
                    }
                }
                .padding(.horizontal, Card.margin)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            // No fade above the bar: content faded under it showed as ghost digits (1.1:1). The bar is
            // opaque with a hairline edge, so what scrolls under it is simply hidden.
            .safeAreaInset(edge: .bottom, spacing: 0) { goButton }
            .navigationTitle("Go to a Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { set(store.moment) }
            .alert("Hours from now", isPresented: $typing) {
                TextField("+3, -1.5 or -2:30", text: $typed)
                    .keyboardType(.numbersAndPunctuation)
                Button("Cancel", role: .cancel) {}
                Button("Go") {
                    if let minutes = TimeShifter.parse(typed) {
                        store.shift(minutes: minutes)
                        dismiss()
                    } else {
                        invalid = true
                    }
                }
            } message: {
                Text("Ahead with + or a plain number, back with −. Hours and minutes work too: 2:30.")
            }
            .alert("That isn't a number of hours", isPresented: $invalid) {
                Button("OK") { typed = ""; typing = true }
            } message: {
                Text("Try +3, -1.5 or -2:30.")
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: Parts

    /// The chosen time, large, with its day and how far away it is.
    private var answer: some View {
        let parts = ClockText.parts(hour: calendar.component(.hour, from: moment), minute: calendar.component(.minute, from: moment), use24h: store.use24h)
        return VStack(spacing: 4) {
            // Medium, as the cards' times (Thin's 3 pt strokes blurred at arm's length); AM/PM is
            // one step lighter (Regular), so the digits stay the heaviest part.
            ClockText.text(parts.digits, suffix: parts.suffix, size: answerSize, weight: .medium)
                .tracking(-1)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text("\(TimeMath.fullDay(moment, in: store.home)) · \(Self.relative(from: store.now, to: moment))")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.white.opacity(Theme.Op.body))
        }
        .frame(maxWidth: .infinity)
        // 12 + 8 (was 24 + 16): at first open the month's third week sat half under the Go bar
        // (its digits cut at ~45% of their height); 20 pt up, that week clears the bar whole.
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.snappy, value: moment)
        .accessibilityElement(children: .combine)
    }

    private var nine: String { store.use24h ? "09:00" : "9\u{2009}AM" }

    private var quickPicks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillChip(title: "Tomorrow \(nine)", isOn: false) { at(daysFromToday: 1, hour: 9) }
                PillChip(title: "Monday \(nine)", isOn: false) {
                    let next = calendar.nextDate(after: store.now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? store.now
                    set(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next)
                }
                PillChip(title: "In a Week", isOn: false) { set(store.now.addingTimeInterval(7 * 86_400)) }
                PillChip(title: "123", systemImage: "number", isOn: false) { typed = ""; invalid = false; typing = true }
                    .accessibilityLabel("Type hours from now")
            }
            .padding(.horizontal, Card.margin)
            .padding(.trailing, 24 - Card.margin)
        }
        // Runs to the screen's edges, and a chip cut there fades out: "scroll for more".
        .chipRowFade()
        .padding(.horizontal, -Card.margin)
    }

    /// Hour, quarter-hour, and AM or PM (or 24-hour), as wheels.
    private var timePicker: some View {
        HStack(spacing: 0) {
            Picker("Hour", selection: hourBinding) {
                ForEach(store.use24h ? Array(0..<24) : Array(1...12), id: \.self) { h in
                    Text(store.use24h ? String(format: "%02d", h) : "\(h)").foregroundStyle(.white).tag(h)
                }
            }
            Picker("Minutes", selection: $quarter) {
                ForEach(0..<4, id: \.self) { q in Text(String(format: ":%02d", q * 15)).foregroundStyle(.white).tag(q) }
            }
            if !store.use24h {
                Picker("AM or PM", selection: pmBinding) {
                    Text("AM").foregroundStyle(.white).tag(false)
                    Text("PM").foregroundStyle(.white).tag(true)
                }
            }
        }
        .pickerStyle(.wheel)
        // Rows are white; UIKit's depth fade still dims the outer rows — contrast of the ±1 values is unmeasured.
        .frame(height: 150)
        .monospacedDigit()
    }

    /// Every city at the chosen moment, with whether it's working there.
    private var cities: some View {
        VStack(spacing: 0) {
            ForEach(store.places) { place in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.body.weight(.medium)).foregroundStyle(.white)
                        if let off = store.showWorkHours ? WorkWeek.offLabel(place, at: moment, start: store.workStart, end: store.workEnd) : nil {
                            Label {
                                Text(off)
                            } icon: {
                                Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.moon)
                            }
                            .labelStyle(StatusLabelStyle())
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h))
                            .font(.title3.weight(.light)).monospacedDigit().foregroundStyle(.white)
                        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
                        if shift != 0 {
                            Text(shift > 0 ? "+\(shift) d" : "−\(-shift) d")
                                .font(.footnote.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                    .fixedSize()
                }
                .frame(minHeight: 44)
                .padding(.vertical, 4)
                if place.id != store.places.last?.id { Divider().overlay(Color.white.opacity(0.2)) }
            }
        }
    }

    private var goButton: some View {
        Button {
            store.jump(to: moment)
            dismiss()
        } label: {
            Text("Go to This Time")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color.white))
                .foregroundStyle(Color.black)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Card.margin)
        .padding(.vertical, 8)
        // Opaque, as the main screen's bars: nothing shows through behind the button.
        .background(Theme.bar, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(Theme.Op.track)).frame(height: 0.5).accessibilityHidden(true)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Time

    /// Shows a moment: its day, and its time rounded to the nearest quarter-hour.
    private func set(_ date: Date) {
        let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded() * 900)
        day = rounded
        hour = calendar.component(.hour, from: rounded)
        quarter = calendar.component(.minute, from: rounded) / 15
    }

    private func at(daysFromToday days: Int, hour h: Int) {
        let start = calendar.startOfDay(for: store.now)
        let target = calendar.date(byAdding: .day, value: days, to: start) ?? start
        set(calendar.date(bySettingHour: h, minute: 0, second: 0, of: target) ?? target)
    }

    /// The hour wheel: 0–23, or 1–12 with AM/PM on its own wheel.
    private var hourBinding: Binding<Int> {
        Binding(
            get: { store.use24h ? hour : (hour % 12 == 0 ? 12 : hour % 12) },
            set: { h in hour = store.use24h ? h : (h % 12) + (hour >= 12 ? 12 : 0) }
        )
    }

    private var pmBinding: Binding<Bool> {
        Binding(get: { hour >= 12 }, set: { pm in hour = hour % 12 + (pm ? 12 : 0) })
    }

    /// "Now", "In 3 d 2 hr", "5 hr ago".
    static func relative(from now: Date, to date: Date) -> String {
        let total = Int((date.timeIntervalSince(now) / 60).rounded())
        if abs(total) < 1 { return "Now" }
        let a = abs(total), d = a / 1440, h = a % 1440 / 60, m = a % 60
        let span = [d > 0 ? "\(d) d" : nil, h > 0 ? "\(h) hr" : nil, d == 0 && m > 0 ? "\(m) min" : nil]
            .compactMap { $0 }.joined(separator: " ")
        return total > 0 ? "In \(span)" : "\(span) ago"
    }
}

/// The month to pick a day from: the month and year with arrows either side, the weekdays
/// ("SUN"…"SAT", from your calendar's first weekday) at 6.6:1, and the days at title3 size. The
/// chosen day is black on a white disc; today, when not chosen, is in the accent.
private struct MonthGrid: View {
    @Binding var day: Date
    let calendar: Calendar
    let today: Date
    /// The first of the month shown; follows `day` until the arrows move it.
    @State private var shown: Date?

    private var month: Date { shown ?? Self.start(of: day, calendar) }

    private static func start(of date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private var title: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        return f.string(from: month)
    }

    private var weekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7].uppercased() }
    }

    /// The month's days, after blanks up to its first weekday.
    private var cells: [Date?] {
        let first = month
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: lead) + days
    }

    private func move(_ months: Int) {
        shown = calendar.date(byAdding: .month, value: months, to: month).map { Self.start(of: $0, calendar) }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { move(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous Month")
                Button { move(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next Month")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.pickerAccent)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityHidden(true)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { cell(date) } else { Color.clear.frame(minHeight: 44) }
                }
            }
        }
        // Seven columns of two digits: capped where they'd no longer fit across.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onChange(of: day) { _, _ in shown = nil }
    }

    private func cell(_ date: Date) -> some View {
        let chosen = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return Button {
            day = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.title3.weight(chosen || isToday ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(chosen ? Color.black : (isToday ? Theme.pickerAccent : Color.white))
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                // The disc fits the cell (its column width or height, whichever is less), so it never
                // runs into the next day at any text size.
                .background {
                    Circle().fill(chosen ? Color.white : Color.clear).aspectRatio(1, contentMode: .fit).padding(2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
