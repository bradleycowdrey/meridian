import SwiftUI

/// The whole app on one screen: the moment you're looking at, one row per city (its time, big,
/// over a strip of its day-and-night hours) and the time dial at the bottom. Drag the dial or any
/// strip sideways to move through time in quarter-hours; tap the date to jump to any day.
struct ContentView: View {
    @EnvironmentObject private var store: CityStore
    /// Owned here and passed down, so the Edit button, the list and the rows all share it.
    @State private var editMode: EditMode = .inactive
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingDate = false
    @State private var copied = false
    @State private var renaming: Place?
    @State private var newName = ""

    private var editing: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.places.isEmpty {
                        emptyState
                    }
                    ForEach(store.places) { place in
                        CityRow(place: place, editing: editing)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Theme.bg)
                            .listRowSeparatorTint(Theme.border)
                            .contextMenu {
                                Button { copy(place) } label: { Label("Copy Time", systemImage: "doc.on.doc") }
                                Button { newName = place.name; renaming = place } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    store.places.removeAll { $0.id == place.id }
                                } label: { Label("Remove", systemImage: "trash") }
                            }
                            .accessibilityAction(named: "Copy Time") { copy(place) }
                            .accessibilityAction(named: "Rename") { newName = place.name; renaming = place }
                            .accessibilityAction(named: "Remove") { store.places.removeAll { $0.id == place.id } }
                            // Sideways drags scrub time, so swipe-to-delete is only in Edit.
                            .deleteDisabled(!editing)
                    }
                    .onDelete { store.remove(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                } header: {
                    // Pinned while the cities scroll underneath.
                    MomentHeader(copied: copied) { showingDate = true }
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bg)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                } footer: {
                    footer
                }
            }
            .listStyle(.plain)
            // Set on the list itself (not only outside the NavigationStack, which keeps its own),
            // so the Edit button, the rows and swipe-to-delete all share this one value.
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .safeAreaInset(edge: .top, spacing: 0) { Theme.crimson.frame(height: 3) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !store.places.isEmpty && !editing { TimeDial() }
            }
            .navigationTitle("Meridian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: Theme.appPage, subject: Text("Meridian"), message: Text(Theme.shareMessage)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Meridian")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.places.isEmpty {
                        Button(editing ? "Done" : "Edit") {
                            withAnimation { editMode = editing ? .inactive : .active }
                        }
                        .fontWeight(editing ? .semibold : .regular)
                    }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!store.canAdd)
                        .accessibilityLabel("Add City")
                    Menu {
                        Button { showingDate = true } label: { Label("Go to Date…", systemImage: "calendar") }
                        Button { copyMoment() } label: { Label("Copy This Moment", systemImage: "doc.on.doc") }
                            .disabled(store.places.isEmpty)
                        ShareLink(item: store.momentText) { Label("Share This Moment", systemImage: "square.and.arrow.up") }
                            .disabled(store.places.isEmpty)
                        Divider()
                        Toggle(isOn: $store.use24h) { Label("24-Hour Time", systemImage: "clock") }
                        Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(isPresented: $showingAdd) { AddCityView(query: Screenshots.screen == "add" ? "san" : "") }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDate) { DateJumpView() }
            // A tick per quarter-hour, a firmer one on each whole hour; only for the user's own moves.
            .sensoryFeedback(trigger: store.userMoves) { _, _ in
                store.onTheHour ? .impact(weight: .medium) : .selection
            }
            .alert("Rename City", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { if let place = renaming { store.rename(place, to: newName) }; renaming = nil }
            }
            .task { await openScreenshotScreen() }
            .onChange(of: store.places.isEmpty) { _, empty in if empty { editMode = .inactive } }
        }
        .environment(\.editMode, $editMode)
        .tint(Theme.cream)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No cities yet").font(.headline).foregroundStyle(Theme.primary)
            Button("Add a City") { showingAdd = true }.buttonStyle(.borderedProminent).tint(Theme.cream).foregroundStyle(Theme.bg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com ↗", destination: Theme.website)
            Link("Terms & Privacy", destination: Theme.legal)
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
        .padding(.top, 16)
    }

    /// Screenshot mode: open the requested screen.
    private func openScreenshotScreen() async {
        guard Screenshots.isActive else { return }
        // After the first layout, so the list and toolbar pick the change up.
        try? await Task.sleep(for: .milliseconds(400))
        switch Screenshots.screen {
        case "add": showingAdd = true
        case "settings": showingSettings = true
        case "date": showingDate = true
        case "edit": editMode = .active
        case "travel": store.jump(to: TimeMath.hourAnchor(store.now).addingTimeInterval(5 * 3600), animated: false)
        default: break
        }
    }

    private func copy(_ place: Place) {
        UIPasteboard.general.string = "\(place.name): \(TimeMath.fullMoment(store.moment, in: place.timeZone, use24h: store.use24h))"
        flashCopied()
    }

    private func copyMoment() {
        UIPasteboard.general.string = store.momentText
        flashCopied()
    }

    private func flashCopied() {
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation { copied = false } }
    }
}

/// "Now, your time" (or how far you've travelled) and the selected moment, which opens the date
/// picker; then whether every city is in working hours.
private struct MomentHeader: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let copied: Bool
    let pickDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if store.isNow { Circle().fill(Theme.crimson).frame(width: 7, height: 7) }
                Text(copied ? "Copied" : relative)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(store.isNow ? Theme.muted : Theme.cream)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if !store.isNow {
                    Button { store.backToNow() } label: {
                        Text("Now")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).frame(height: 30)
                            .background(Capsule().fill(Theme.cream))
                            .foregroundStyle(Theme.bg)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityLabel("Back to now")
                }
            }
            .frame(height: 30)

            Button(action: pickDate) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TimeMath.fullMoment(store.moment, in: .current, use24h: store.use24h))
                        .font(.system(.title, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Image(systemName: "calendar")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose a date and time")

            if let overlap {
                HStack(spacing: 6) {
                    Image(systemName: store.outsideWorkHours.isEmpty ? "checkmark.circle.fill" : "moon.zzz")
                        .foregroundStyle(store.outsideWorkHours.isEmpty ? Theme.cream : Theme.faint)
                    Text(overlap).foregroundStyle(Theme.muted).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
                .font(.footnote)
            }
        }
    }

    private var relative: String {
        if store.isNow { return "Now, your time" }
        // From the real time now, to the nearest 5 minutes ("In 4 h 20 min").
        let total = Int((store.moment.timeIntervalSince(store.now) / 300).rounded()) * 5
        if total == 0 { return "Now" }
        let days = abs(total) / 1440, hours = abs(total) % 1440 / 60, minutes = abs(total) % 60
        let span = [days > 0 ? "\(days) d" : nil, hours > 0 ? "\(hours) h" : nil, minutes > 0 ? "\(minutes) min" : nil]
            .compactMap { $0 }.joined(separator: " ")
        return total > 0 ? "In \(span)" : "\(span) ago"
    }

    /// The meeting planner in one line.
    private var overlap: String? {
        guard store.showWorkHours, store.places.count > 1 else { return nil }
        let out = store.outsideWorkHours
        if out.isEmpty { return "Working hours in every city" }
        if out.count == store.places.count { return "Outside working hours everywhere" }
        let names = out.prefix(3).map(\.name).joined(separator: ", ")
        return "Outside working hours: \(names)\(out.count > 3 ? " +\(out.count - 3)" : "")"
    }
}

/// One city: its name and how it relates to you, its time at the selected moment, and its hours.
struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 32
    let place: Place
    /// Passed in rather than read from the environment, which List overrides for its rows.
    let editing: Bool

    var body: some View {
        let moment = store.moment
        let cal = place.calendar
        let hour = cal.component(.hour, from: moment), minute = cal.component(.minute, from: moment)
        // Side by side normally; stacked at accessibility text sizes so nothing is cut off.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        VStack(alignment: .leading, spacing: 8) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text(detail(moment))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if editing {
                    HStack(spacing: 8) {
                        Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h)).foregroundStyle(Theme.secondary)
                        Text(place.offsetLabel(at: moment)).foregroundStyle(Theme.muted)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                } else {
                    clock(hour: hour, minute: minute)
                }
            }
            if !editing {
                HourStrip(place: place)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.name), \(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h)), \(detail(moment))")
    }

    private func clock(hour: Int, minute: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(store.use24h ? String(format: "%02d:%02d", hour, minute)
                              : "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))")
                .font(.system(size: clockSize, weight: .medium))
                .foregroundStyle(Theme.primary)
                .contentTransition(.numericText())
            if !store.use24h {
                Text(hour < 12 ? "AM" : "PM")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// "Today · +8 h", "Tomorrow · +5:30 h", "Wed · −1 h", "Today · Your time".
    private func detail(_ moment: Date) -> String {
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        let day = store.isNow ? (shift == 0 ? "Today" : shift > 0 ? "Tomorrow" : "Yesterday")
                              : TimeMath.weekday(moment, in: place.timeZone)
        let diff = place.timeZone.secondsFromGMT(for: moment) - TimeZone.current.secondsFromGMT(for: moment)
        if diff == 0 {
            return "\(day) · \(place.timeZone.identifier == TimeZone.current.identifier ? "Your time" : "Same time")"
        }
        let h = abs(diff) / 3600, m = abs(diff) % 3600 / 60
        return "\(day) · \(diff > 0 ? "+" : "−")\(h)\(m > 0 ? ":\(String(format: "%02d", m))" : "") h"
    }
}

/// A city's hours as day-and-night tiles sliding under a fixed centre line, which marks the
/// selected moment. Tiles sit on the city's own hour boundaries, so half-hour zones line up
/// truthfully against the others. Drag sideways to move through time.
struct HourStrip: View {
    static let hourWidth: CGFloat = 38
    private static let height: CGFloat = 36
    @EnvironmentObject private var store: CityStore
    let place: Place

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let moment = store.moment
            let cal = place.calendar
            let start = cal.dateInterval(of: .hour, for: moment)?.start ?? moment
            let reach = Int(center / Self.hourWidth) + 2
            let hours = (-reach...reach).map { start.addingTimeInterval(Double($0) * 3600) }
            ZStack(alignment: .topLeading) {
                ForEach(hours, id: \.self) { at in
                    tile(at, cal: cal)
                        .frame(width: Self.hourWidth - 3, height: Self.height)
                        .offset(x: center + CGFloat(at.timeIntervalSince(moment) / 3600) * Self.hourWidth + 1.5, y: 6)
                }
                // The exact minute: notches above and below, so they never cover an hour label.
                Capsule().fill(Theme.cream).frame(width: 3, height: 5).offset(x: center - 1.5)
                Capsule().fill(Theme.cream).frame(width: 3, height: 5).offset(x: center - 1.5, y: Self.height + 7)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            // Tap an hour to go to it.
            .onTapGesture { location in
                let tapped = moment.addingTimeInterval(Double((location.x - center) / Self.hourWidth) * 3600)
                store.jump(to: cal.dateInterval(of: .hour, for: tapped)?.start ?? tapped)
            }
        }
        .frame(height: Self.height + 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                                     .init(color: .black, location: 0.93), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .modifier(Scrub(pointsPerHour: Self.hourWidth))
        .accessibilityHidden(true)
    }

    private func tile(_ at: Date, cal: Calendar) -> some View {
        let hour = cal.component(.hour, from: at)
        let style = DayColor.style(at: Double(hour) + 0.5)
        let dim = store.showWorkHours && !store.isWorkHour(hour)
        return VStack(spacing: 1) {
            Group {
                if store.use24h {
                    Text(String(format: "%02d", hour))
                } else {
                    Text("\(hour % 12 == 0 ? 12 : hour % 12)") + Text(hour < 12 ? "a" : "p").font(.system(size: 9, weight: .semibold))
                }
            }
            .font(.system(.footnote, weight: .medium))
            .monospacedDigit()
            if hour == 0 {
                Text(TimeMath.weekday(at, in: place.timeZone)).font(.system(size: 8, weight: .semibold)).textCase(.uppercase)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.fill.opacity(dim ? 0.6 : 1)))
        .overlay(alignment: .leading) {
            if hour == 0 { Capsule().fill(Theme.crimson).frame(width: 2).padding(.vertical, 8).offset(x: -2.5) }
        }
        .overlay {
            // The hour that holds the selected moment.
            if at <= store.moment && store.moment < at.addingTimeInterval(3600) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cream, lineWidth: 2)
            }
        }
    }
}

/// The dial docked at the bottom: a ruler of quarter-hours on your clock, centred on the selected
/// moment. Drag it to move through time; with VoiceOver, swipe up or down to step an hour.
struct TimeDial: View {
    static let hourWidth: CGFloat = 72
    @EnvironmentObject private var store: CityStore

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let center = geo.size.width / 2
                let moment = store.moment
                let first = TimeMath.hourAnchor(moment)
                let reach = (Int(center / Self.hourWidth) + 2) * 4
                let quarters = (-reach...reach).map { first.addingTimeInterval(Double($0) * 900) }
                ZStack(alignment: .topLeading) {
                    ForEach(quarters, id: \.self) { q in
                        mark(q)
                            .frame(width: 60)
                            .offset(x: center + CGFloat(q.timeIntervalSince(moment) / 3600) * Self.hourWidth - 30, y: 6)
                    }
                    Capsule().fill(Theme.crimson).frame(width: 3, height: 26).offset(x: center - 1.5)
                }
            }
            .frame(height: 40)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            if !store.hasScrubbed {
                Text("Drag to change the time")
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .font(.caption2)
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.top, 10).padding(.bottom, store.hasScrubbed ? 0 : 4)
        .background(Theme.bg.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) })
        .contentShape(Rectangle())
        .modifier(Scrub(pointsPerHour: Self.hourWidth))
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(TimeMath.fullMoment(store.moment, in: .current, use24h: store.use24h))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.travel(1)
            case .decrement: store.travel(-1)
            @unknown default: break
            }
        }
    }

    private func mark(_ q: Date) -> some View {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: q), minute = cal.component(.minute, from: q)
        return VStack(spacing: 4) {
            Rectangle()
                .fill(minute == 0 ? Theme.secondary : Theme.faint)
                .frame(width: minute == 0 ? 1.5 : 1, height: minute == 0 ? 14 : 7)
            if minute == 0 {
                Text(hour == 0 ? TimeMath.weekday(q, in: .current).uppercased()
                               : store.use24h ? String(format: "%02d:00", hour) : "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")")
                    .font(.system(.caption2, weight: hour == 0 ? .semibold : .medium))
                    .foregroundStyle(hour == 0 ? Theme.cream : Theme.muted)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }
}

/// Sideways drag to scrub through time in quarter-hours. Locks to the first direction moved, so
/// vertical drags still scroll the list.
private struct Scrub: ViewModifier {
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
                    let next = start + Int((minutes / 15).rounded()) * 15
                    store.scrub(to: next)
                }
                .onEnded { _ in
                    base = nil
                    horizontal = nil
                }
        )
    }
}
