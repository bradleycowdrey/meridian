import SwiftUI

/// The whole app on one screen: the moment you're looking at, one row per city (its time, large,
/// over a slim day-and-night bar of its hours). Drag any bar sideways to move through time in
/// quarter-hours; tap the date to jump to any day.
struct ContentView: View {
    @EnvironmentObject private var store: CityStore
    @State private var showingEdit = false
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingDate = false
    @State private var copied = false
    @State private var renaming: Place?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            screen
        }
        .tint(Theme.cream)
    }

    // The body is split into parts so the Swift compiler can type-check each one quickly.

    private var screen: some View {
        styledList
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAdd) { AddCityView(query: Screenshots.screen == "add" ? "san" : "") }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDate) { DateJumpView() }
            .sheet(isPresented: $showingEdit) { EditCitiesView() }
            // A tick per quarter-hour, a firmer one on each whole hour; only for the user's own moves.
            .sensoryFeedback(trigger: store.userMoves) { _, _ in haptic }
            .alert("Rename City", isPresented: isRenaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { finishRename() }
            }
            .task { await openScreenshotScreen() }
    }

    private var styledList: some View {
        cityList
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .safeAreaInset(edge: .top, spacing: 0) { Theme.crimson.frame(height: 3) }
            .navigationTitle("Meridian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    private var cityList: some View {
        List {
            Section {
                if store.places.isEmpty {
                    emptyState
                }
                ForEach(store.places) { place in
                    row(place)
                }
            } header: {
                // Pinned while the cities scroll underneath.
                MomentHeader(copied: copied) { showingDate = true }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg)
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            } footer: {
                footer
            }
        }
    }

    private func row(_ place: Place) -> some View {
        CityRow(place: place)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.border)
            .contextMenu {
                Button { copy(place) } label: { Label("Copy Time", systemImage: "doc.on.doc") }
                if !place.isMyLocation {
                    Button { newName = place.name; renaming = place } label: { Label("Rename", systemImage: "pencil") }
                }
                Button(role: .destructive) {
                    store.remove(place)
                } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityAction(named: "Copy Time") { copy(place) }
            .accessibilityAction(named: "Rename") { newName = place.name; renaming = place }
            .accessibilityAction(named: "Remove") { store.remove(place) }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ShareLink(item: Theme.appPage, subject: Text("Meridian"), message: Text(Theme.shareMessage)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Meridian")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !store.places.isEmpty { Button("Edit") { showingEdit = true } }
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

    private var haptic: SensoryFeedback {
        store.onTheHour ? .impact(weight: .medium) : .selection
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func finishRename() {
        if let place = renaming { store.rename(place, to: newName) }
        renaming = nil
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
        case "edit": showingEdit = true
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

/// The moment you're looking at: a small "NOW" (or "IN 4 HR 20 MIN") over the date and time,
/// which opens the date picker; a Now button when you've moved; and the meeting planner as one
/// quiet line.
private struct MomentHeader: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let copied: Bool
    let pickDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: pickDate) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if store.isNow { Circle().fill(Theme.crimson).frame(width: 6, height: 6) }
                            Text(copied ? "COPIED" : relative.uppercased())
                                .font(.caption.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(store.isNow ? Theme.muted : Theme.cream)
                                .contentTransition(.numericText())
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(TimeMath.fullMoment(store.moment, in: .current, use24h: store.use24h))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .monospacedDigit()
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose a date and time. Swipe up or down to move an hour.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: store.travel(1)
                    case .decrement: store.travel(-1)
                    @unknown default: break
                    }
                }
                Spacer(minLength: 0)
                if !store.isNow {
                    Button { store.backToNow() } label: {
                        Text("Now")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).frame(height: 32)
                            .background(Capsule().fill(Theme.cream))
                            .foregroundStyle(Theme.bg)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityLabel("Back to now")
                }
            }
            if !store.hasScrubbed && !store.places.isEmpty && !Screenshots.isActive {
                Label("Drag any bar to change the time", systemImage: "hand.draw")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            if let overlap {
                HStack(spacing: 6) {
                    Image(systemName: store.outsideWorkHours.isEmpty ? "checkmark.circle.fill" : "moon.zzz.fill")
                        .foregroundStyle(store.outsideWorkHours.isEmpty ? Theme.cream : Theme.faint)
                    Text(overlap).foregroundStyle(Theme.secondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
                .font(.footnote)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.tile))
            }
        }
    }

    private var relative: String {
        if store.isNow { return "Now" }
        // From the real time now, to the nearest 5 minutes ("In 4 hr 20 min").
        let total = Int((store.moment.timeIntervalSince(store.now) / 300).rounded()) * 5
        if total == 0 { return "Now" }
        let days = abs(total) / 1440, hours = abs(total) % 1440 / 60, minutes = abs(total) % 60
        let span = [days > 0 ? "\(days) d" : nil, hours > 0 ? "\(hours) hr" : nil, minutes > 0 ? "\(minutes) min" : nil]
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

/// One city, in the manner of Apple's Clock: how it relates to you and its name on the left, its
/// time large and light on the right; then a slim day-and-night bar of its hours.
struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 40
    let place: Place

    var body: some View {
        let moment = store.moment
        let cal = place.calendar
        let hour = cal.component(.hour, from: moment), minute = cal.component(.minute, from: moment)
        // Side by side normally; stacked at accessibility text sizes so nothing is cut off.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 8))
        VStack(alignment: .leading, spacing: 12) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail(moment))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        Text(place.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                        if place.isMyLocation {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                clock(hour: hour, minute: minute)
            }
            DayBar(place: place)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.name)\(place.isMyLocation ? ", My Location" : ""), \(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h)), \(detail(moment))")
    }

    private func clock(hour: Int, minute: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(store.use24h ? String(format: "%02d:%02d", hour, minute)
                              : "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))")
                .font(.system(size: clockSize, weight: .light))
                .foregroundStyle(Theme.primary)
                .contentTransition(.numericText())
            if !store.use24h {
                Text(hour < 12 ? "AM" : "PM")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
            }
            // "+1 d" / "−1 d" when the city is on another day, as in the Mac app and widgets.
            let shift = TimeMath.dayShift(store.moment, zone: place.timeZone)
            if shift != 0 {
                Text(shift > 0 ? "+\(shift) d" : "−\(-shift) d")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.border))
                    .foregroundStyle(Theme.cream)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// "+8 hr · UTC+1", "+5:30 hr · UTC+5:30", "Your time · UTC−7".
    private func detail(_ moment: Date) -> String {
        let utc = place.offsetLabel(at: moment)
        let diff = place.timeZone.secondsFromGMT(for: moment) - TimeZone.current.secondsFromGMT(for: moment)
        if diff == 0 {
            return "\(place.timeZone.identifier == TimeZone.current.identifier ? "Your time" : "Same time") · \(utc)"
        }
        let h = abs(diff) / 3600, m = abs(diff) % 3600 / 60
        return "\(diff > 0 ? "+" : "−")\(h)\(m > 0 ? ":\(String(format: "%02d", m))" : "") hr · \(utc)"
    }
}

/// Twelve hours of a city's sky in one slim bar: six before the selected moment and six after,
/// light by day and dark by night, dimmer outside working hours, with a crimson tick at midnight.
/// A cream knob marks the selected moment; the city's hours are labelled underneath. Drag it to
/// move through time; tap to go to that hour.
struct DayBar: View {
    static let hoursShown: Double = 12
    private static let barHeight: CGFloat = 8
    @EnvironmentObject private var store: CityStore
    @State private var width: CGFloat = 340
    let place: Place

    private var pointsPerHour: CGFloat { max(1, width / CGFloat(Self.hoursShown)) }

    var body: some View {
        let moment = store.moment
        let cal = place.calendar
        let start = moment.addingTimeInterval(-Self.hoursShown / 2 * 3600)
        VStack(spacing: 6) {
            Canvas { context, size in
                let perHour = size.width / CGFloat(Self.hoursShown)
                let slices = Int(Self.hoursShown * 4)
                for i in 0..<slices {
                    let at = start.addingTimeInterval(Double(i) * 900 + 450)
                    let parts = cal.dateComponents([.hour, .minute], from: at)
                    let hour = parts.hour ?? 0
                    let dim = store.showWorkHours && !store.isWorkHour(hour)
                    let fill = Self.tone(DayColor.style(at: Double(hour) + Double(parts.minute ?? 0) / 60).fill, dim: dim)
                    // Opaque and slightly overlapping, so no seams show between slices.
                    let rect = CGRect(x: CGFloat(i) * perHour / 4, y: 0, width: perHour / 4 + 1, height: size.height)
                    context.fill(Path(rect), with: .color(fill))
                }
                for midnight in marks(from: start, cal: cal).filter(\.isMidnight) {
                    let x = CGFloat(midnight.date.timeIntervalSince(start) / 3600) * perHour
                    context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.crimson))
                }
            }
            .frame(height: Self.barHeight)
            .clipShape(Capsule())
            .overlay {
                Circle()
                    .fill(Theme.cream)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 3))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            // The city's hours every three hours, and the weekday at midnight.
            ZStack(alignment: .leading) {
                ForEach(marks(from: start, cal: cal), id: \.date) { mark in
                    Text(mark.label)
                        .font(.system(.caption2, weight: mark.isMidnight ? .semibold : .regular))
                        .foregroundStyle(mark.isMidnight ? Theme.cream : Theme.muted)
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: CGFloat(mark.date.timeIntervalSince(start) / 3600) * pointsPerHour, y: 6)
                }
            }
            .frame(height: 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let tapped = start.addingTimeInterval(Double(location.x / pointsPerHour) * 3600)
            store.jump(to: cal.dateInterval(of: .hour, for: tapped)?.start ?? tapped)
        }
        .modifier(Scrub(pointsPerHour: pointsPerHour))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }

    private struct Mark { let date: Date; let label: String; let isMidnight: Bool }

    /// The sky colour, kept visible at night (never darker than the border tone) and, outside
    /// working hours, mixed halfway towards the background (opaque, so slices never show seams).
    private static func tone(_ color: Color, dim: Bool) -> Color {
        let env = EnvironmentValues()
        let c = color.resolve(in: env), floor = Theme.border.resolve(in: env), bg = Theme.bg.resolve(in: env)
        var r = c.red, g = c.green, b = c.blue
        if 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.2126 * floor.red + 0.7152 * floor.green + 0.0722 * floor.blue {
            (r, g, b) = (floor.red, floor.green, floor.blue)
        }
        if dim { (r, g, b) = ((r + bg.red) / 2, (g + bg.green) / 2, (b + bg.blue) / 2) }
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b))
    }

    /// Local hours divisible by three inside the bar (not at its very ends), and midnights.
    private func marks(from start: Date, cal: Calendar) -> [Mark] {
        guard let first = cal.dateInterval(of: .hour, for: start)?.end else { return [] }
        var marks: [Mark] = []
        var at = first
        let end = start.addingTimeInterval(Self.hoursShown * 3600)
        while at < end {
            let hour = cal.component(.hour, from: at)
            let edge = at.timeIntervalSince(start) < 1800 || end.timeIntervalSince(at) < 1800
            if !edge && (hour % 3 == 0) {
                let label = hour == 0 ? TimeMath.weekday(at, in: place.timeZone).uppercased()
                    : store.use24h ? String(format: "%02d", hour)
                    : "\(hour % 12 == 0 ? 12 : hour % 12)\u{2009}\(hour < 12 ? "AM" : "PM")"
                marks.append(Mark(date: at, label: label, isMidnight: hour == 0))
            }
            at = at.addingTimeInterval(3600)
        }
        return marks
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
