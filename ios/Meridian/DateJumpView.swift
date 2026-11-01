import SwiftUI

/// Go to a day and time (on your clock), in quarter-hours, and see every city at that moment
/// before going there: the answer at the top, quick picks, a calendar, the time, your cities.
struct DateJumpView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    /// The chosen day (any time on it) and the time on it, in quarter-hours.
    @State private var day = Date()
    @State private var hour = 9
    @State private var quarter = 0
    /// 123: type hours from now ("+3", "-1.5", "-2:30").
    @State private var typing = false
    @State private var typed = ""
    @State private var invalid = false

    private var calendar: Calendar { Calendar.current }

    /// The chosen moment: the day at hour:minute on your clock.
    private var moment: Date {
        calendar.date(bySettingHour: hour, minute: quarter * 15, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    answer
                    quickPicks
                    card { DatePicker("Day", selection: $day, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden() }
                    card { timePicker }
                    if !store.places.isEmpty { card { cities } }
                }
                .padding(.horizontal, Card.margin)
                .padding(.bottom, 96)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) { goButton }
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
        .tint(Theme.cream)
        .preferredColorScheme(.dark)
    }

    // MARK: Parts

    /// The chosen time, large, with its day and how far away it is.
    private var answer: some View {
        VStack(spacing: 4) {
            Text(TimeMath.time(moment, in: .current, use24h: store.use24h))
                .font(.system(size: 44, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Theme.primary)
                .contentTransition(.numericText())
            Text("\(Self.day.string(from: moment)) · \(Self.relative(from: store.now, to: moment))")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .animation(.snappy, value: moment)
        .accessibilityElement(children: .combine)
    }

    private var nine: String { store.use24h ? "09:00" : "9\u{2009}AM" }

    private var quickPicks: some View {
        HStack(spacing: 8) {
            chip("Tomorrow \(nine)") { at(daysFromToday: 1, hour: 9) }
            chip("Monday \(nine)") {
                let next = calendar.nextDate(after: store.now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? store.now
                set(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next)
            }
            chip("In a Week") { set(store.now.addingTimeInterval(7 * 86_400)) }
            chip("123") { typed = ""; invalid = false; typing = true }
                .frame(maxWidth: 56)
                .accessibilityLabel("Type hours from now")
        }
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
                        Text(place.name).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                        if let off = store.showWorkHours ? WorkWeek.offLabel(place, at: moment, start: store.workStart, end: store.workEnd) : nil {
                            Label(off, systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h))
                            .font(.title3.weight(.light)).monospacedDigit().foregroundStyle(Theme.primary)
                        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
                        if shift != 0 {
                            Text(shift > 0 ? "+\(shift) d" : "−\(-shift) d")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.border))
                                .foregroundStyle(Theme.cream)
                        }
                    }
                    .fixedSize()
                }
                .padding(.vertical, 10)
                if place.id != store.places.last?.id { Divider().overlay(Theme.border) }
            }
        }
    }

    private var goButton: some View {
        Button {
            store.jump(to: moment)
            dismiss()
        } label: {
            Text("Go to This Time")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Theme.cream))
                .foregroundStyle(Theme.bg)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Card.margin)
        .padding(.top, 8)
        .background(Theme.bg.opacity(0.95))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).fill(Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5).allowsHitTesting(false))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(Theme.tile))
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5).allowsHitTesting(false))
                .foregroundStyle(Theme.secondary)
        }
        .buttonStyle(.plain)
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

    /// "Tue 9 Jun", as everywhere else in the app.
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

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
