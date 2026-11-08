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
                    VStack(alignment: .leading, spacing: 10) {
                        CardCaption("Date", "calendar")
                        DatePicker("Day", selection: $day, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.timeZone, store.home)
                            // Not white. UIKit draws today, when selected, white on a solid disc of the tint
                            // (switchOn keeps that legible); any other selected day in the tint on a light disc of it.
                            .tint(store.homeCalendar.isDateInToday(day) ? Theme.switchOn : Theme.pickerAccent)
                    }
                    .glassCard()
                    VStack(alignment: .leading, spacing: 10) {
                        CardCaption("Time", "clock")
                        timePicker
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
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
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
            ClockText.text(parts.digits, suffix: parts.suffix, size: answerSize, weight: .thin)
                .tracking(-2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text("\(TimeMath.fullDay(moment, in: store.home)) · \(Self.relative(from: store.now, to: moment))")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.white.opacity(Theme.Op.body))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 16)
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
        }
        // Runs to the screen's edges, so a cut-off chip reads as "scroll for more".
        .padding(.horizontal, -Card.margin)
    }

    /// Hour, quarter-hour, and AM or PM (or 24-hour), as wheels.
    private var timePicker: some View {
        HStack(spacing: 0) {
            Picker("Hour", selection: hourBinding) {
                ForEach(store.use24h ? Array(0..<24) : Array(1...12), id: \.self) { h in
                    Text(store.use24h ? String(format: "%02d", h) : "\(h)").tag(h)
                }
            }
            Picker("Minutes", selection: $quarter) {
                ForEach(0..<4, id: \.self) { q in Text(String(format: ":%02d", q * 15)).tag(q) }
            }
            if !store.use24h {
                Picker("AM or PM", selection: pmBinding) {
                    Text("AM").tag(false)
                    Text("PM").tag(true)
                }
            }
        }
        .pickerStyle(.wheel)
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
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        // A short fade above the bar, so a card scrolled under it reads as "more below", not as cut off.
        .background(alignment: .top) {
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .offset(y: -24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(Theme.Op.track)) }
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
