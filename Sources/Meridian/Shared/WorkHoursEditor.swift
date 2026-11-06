import SwiftUI

/// One city's working days and hours (Mac and iPhone). Starts from the city's own, or the usual
/// week where it is and the hours in Settings; saves only what differs from those.
struct WorkHoursEditor: View {
    let place: Place
    /// The hours in Settings, used when the city has none of its own.
    let defaultStart: Int
    let defaultEnd: Int
    let use24h: Bool
    let save: (_ days: Set<Int>?, _ start: Int?, _ end: Int?) -> Void

    @State private var days: Set<Int> = []
    @State private var start = 9
    @State private var end = 18

    private var usualDays: Set<Int> { WorkWeek.usualDays(zoneID: place.timeZoneID) }
    /// The hours most days keep there, to the whole hour (Settings' hours where none are known).
    private var usualStart: Int { WorkWeek.typicalHours(zoneID: place.timeZoneID).map { Int($0.start) } ?? defaultStart }
    private var usualEnd: Int { WorkWeek.typicalHours(zoneID: place.timeZoneID).map { Int($0.end.rounded(.up)) } ?? defaultEnd }
    private var isUsual: Bool { days == usualDays && start == usualStart && end == usualEnd }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = days.contains(day)
                        Button {
                            if on { days.remove(day) } else { days.insert(day) }
                            commit()
                        } label: {
                            Text(Self.initials[day - 1])
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Capsule().fill(on ? Color.primary.opacity(0.9) : Color.primary.opacity(0.1)))
                                .foregroundStyle(on ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar(identifier: .gregorian).weekdaySymbols[day - 1])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            } header: {
                Text("Working days")
            } footer: {
                Text("Usual in \(place.name): \(WorkWeek.describeUsual(zoneID: place.timeZoneID, use24h: use24h)).")
            }
            Section("Working hours") {
                Picker("Starts", selection: $start) {
                    ForEach(0..<24, id: \.self) { Text(label($0)).tag($0) }
                }
                Picker("Ends", selection: $end) {
                    ForEach(1...24, id: \.self) { Text(label($0)).tag($0) }
                }
            }
            Section {
                Button("Use the Usual Days and Hours") {
                    days = usualDays; start = usualStart; end = usualEnd
                    commit()
                }
                .disabled(isUsual)
            }
        }
        .onAppear {
            days = place.workDays ?? usualDays
            start = place.workStart ?? usualStart
            end = place.workEnd ?? usualEnd
        }
        .onChange(of: start) { _, _ in commit() }
        .onChange(of: end) { _, _ in commit() }
    }

    /// Keeps only what differs from the usual, so a city follows Settings and the country's week
    /// unless it was changed.
    private func commit() {
        save(days == usualDays ? nil : days, start == usualStart ? nil : start, end == usualEnd ? nil : end)
    }

    private func label(_ hour: Int) -> String {
        if use24h { return String(format: "%02d:00", hour) }
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\u{2009}\(hour % 24 < 12 ? "AM" : "PM")"
    }

    private static let initials = ["S", "M", "T", "W", "T", "F", "S"]
}
