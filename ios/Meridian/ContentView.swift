import SwiftUI

/// The whole app on one screen: the moment you're looking at, one row per city (its time, large,
/// over a slim day-and-night bar of its hours). Drag any bar sideways to move through time in
/// quarter-hours; tap the date to jump to any day.
struct ContentView: View {
    @EnvironmentObject private var store: CityStore
    /// Search to add a city, right above the cards (as in Apple's Weather and Two Degrees).
    @State private var query = ""
    /// Edit List (from ⋯): reorder and remove in place, then Done.
    @State private var editMode: EditMode = .inactive
    @State private var showingSettings = false
    @State private var showingDate = false
    @State private var copied = false
    @State private var renaming: Place?
    /// The card tapped: its actions show in a dialog.
    @State private var actionsFor: Place?
    /// The city whose working days and hours are being edited.
    @State private var workFor: Place?
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
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDate) { DateJumpView() }
            // A tick per quarter-hour, a firmer one on each whole hour; only for the user's own moves.
            .sensoryFeedback(trigger: store.userMoves) { _, _ in haptic }
            .alert("Rename City", isPresented: isRenaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { finishRename() }
            }
            .confirmationDialog(actionsFor?.name ?? "", isPresented: showingActions, titleVisibility: .visible, presenting: actionsFor) { place in
                Button("Copy Time") { copy(place) }
                Button("Working Days & Hours") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { workFor = place }
                }
                if !place.isMyLocation {
                    Button("Rename") {
                        newName = place.name
                        // After the dialog has gone, so the rename alert can show.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { renaming = place }
                    }
                }
                Button("Remove", role: .destructive) { store.remove(place) }
            } message: { place in
                Text("\(TimeMath.fullMoment(store.moment, in: place.timeZone, use24h: store.use24h)) · \(place.offsetLabel(at: store.moment))")
            }
            .sheet(item: $workFor) { place in
                NavigationStack {
                    WorkHoursEditor(place: place, defaultStart: store.workStart, defaultEnd: store.workEnd, use24h: store.use24h) {
                        store.setWork(for: place, days: $0, start: $1, end: $2)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.bg)
                    .navigationTitle(place.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { workFor = nil } } }
                }
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
            .task { await openScreenshotScreen() }
    }

    private var showingActions: Binding<Bool> {
        Binding(get: { actionsFor != nil }, set: { if !$0 { actionsFor = nil } })
    }

    private var styledList: some View {
        cityList
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .safeAreaInset(edge: .top, spacing: 0) { Theme.crimson.frame(height: 3) }
            .navigationTitle("Meridian")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Add a city, SFO, PST, UTC+5")
            .autocorrectionDisabled()
            .environment(\.editMode, $editMode)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    private var cityList: some View {
        List {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
            } else {
                cards
            }
        }
    }

    /// Search results in place of the cards; tap one to add it.
    @ViewBuilder private var searchResults: some View {
        if !store.canAdd {
            Text("You can keep up to \(CityStore.maxPlaces) cities. Remove one to add another.")
                .foregroundStyle(Theme.muted)
                .listRowBackground(Theme.bg)
        }
        let results = CityDirectory.search(query)
        if results.isEmpty {
            Text("No places match “\(query)”. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.")
                .foregroundStyle(Theme.muted)
                .listRowBackground(Theme.bg)
        }
        ForEach(results) { entry in
            let added = store.contains(entry)
            Button {
                store.add(entry)
                query = ""
            } label: {
                SearchResultRow(entry: entry, added: added)
            }
            .disabled(added || !store.canAdd)
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.border)
            .accessibilityHint(added ? "Already added" : "Adds \(entry.name)")
        }
    }

    @ViewBuilder private var cards: some View {
        Section {
            if store.places.isEmpty {
                emptyState
            }
            ForEach(store.places) { place in
                row(place)
            }
            // Remove and reorder in Edit List only: a sideways swipe on a card drags its day bar.
            .onDelete { store.remove(at: $0) }
            .onMove { store.move(from: $0, to: $1) }
            // The last row, not a section footer: a plain list pins footers to the bottom
            // of the screen on a black band, over the home indicator.
            footer
                .listRowInsets(EdgeInsets(top: 8, leading: Card.margin, bottom: 24, trailing: Card.margin))
                .listRowBackground(Theme.bg)
                .listRowSeparator(.hidden)
        } header: {
            // Pinned while the cities scroll underneath.
            MomentHeader(copied: copied) { showingDate = true }
                .padding(.horizontal, Card.margin).padding(.top, 14).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg)
                .listRowInsets(EdgeInsets())
                .textCase(nil)
        }
    }

    private func row(_ place: Place) -> some View {
        // Each city is a card: 16 pt from the screen edges, 16 pt inside, 12 pt between cards
        // (Apple's standard margins; continuous corners like the system's own cards), with a
        // hairline edge so cards stand apart on the dark background. Each card has its own
        // actions: tap for them, or touch and hold for the menu. No swipe to remove: a sideways
        // swipe drags the day bar, which moves the time for every city.
        CityRow(place: place, editing: editMode.isEditing)
            .contentShape(Rectangle())
            .onTapGesture { if !editMode.isEditing { actionsFor = place } }
            .deleteDisabled(!editMode.isEditing)
            .moveDisabled(!editMode.isEditing)
            .listRowInsets(EdgeInsets(top: Card.gap / 2 + Card.padding, leading: Card.margin + Card.padding,
                                      bottom: Card.gap / 2 + Card.padding, trailing: Card.margin + Card.padding))
            .listRowBackground(
                RoundedRectangle(cornerRadius: Card.radius, style: .continuous)
                    .fill(Theme.tile)
                    .overlay(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
                    .padding(.horizontal, Card.margin)
                    .padding(.vertical, Card.gap / 2)
            )
            .listRowSeparator(.hidden)
            .contextMenu {
                Button { copy(place) } label: { Label("Copy Time", systemImage: "doc.on.doc") }
                Button { workFor = place } label: { Label("Working Days & Hours", systemImage: "briefcase") }
                if !place.isMyLocation {
                    Button { newName = place.name; renaming = place } label: { Label("Rename", systemImage: "pencil") }
                }
                Button(role: .destructive) {
                    store.remove(place)
                } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityAction(named: "Copy Time") { copy(place) }
            .accessibilityAction(named: "Rename") { if !place.isMyLocation { newName = place.name; renaming = place } }
            .accessibilityAction(named: "Remove") { store.remove(place) }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editMode.isEditing {
                Button("Done") { withAnimation { editMode = .inactive } }.fontWeight(.semibold)
            } else {
                shareMenu
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { query = ""; withAnimation { editMode = .active } } label: { Label("Edit List", systemImage: "pencil") }
                    .disabled(store.places.isEmpty)
                Divider()
                Button { showingDate = true } label: { Label("Go to Date…", systemImage: "calendar") }
                Button { copyMoment() } label: { Label("Copy This Moment", systemImage: "doc.on.doc") }
                    .disabled(store.places.isEmpty)
                Divider()
                Toggle(isOn: $store.use24h) { Label("24-Hour Time", systemImage: "clock") }
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                Divider()
                Link(destination: Theme.macDownload) { Label("Get Meridian for Mac", systemImage: "laptopcomputer") }
                Link(destination: Theme.legal) { Label("Terms & Privacy", systemImage: "doc.text") }
                Link(destination: Theme.issues) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    /// Share, as in Cowdrey.MD: the system share sheet for Meridian or this moment, or copy a link
    /// or a ready-to-send message.
    private var shareMenu: some View {
        Menu {
            ShareLink(item: Theme.appPage, subject: Text("Meridian"), message: Text(Theme.shareMessage),
                      preview: SharePreview("Meridian: every time zone at a glance", image: Image("Mark"))) {
                Label("Share Meridian…", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: store.momentText, subject: Text("Times for \(TimeMath.fullMoment(store.moment, in: .current, use24h: store.use24h))"),
                      preview: SharePreview("This moment in every city")) {
                Label("Share This Moment…", systemImage: "clock")
            }
            .disabled(store.places.isEmpty)
            Divider()
            Button { UIPasteboard.general.url = Theme.appPage; flashCopied() } label: { Label("Copy Link", systemImage: "link") }
            Button { UIPasteboard.general.string = Theme.messageToSend; flashCopied() } label: {
                Label("Copy a Message to Send", systemImage: "text.bubble")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
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
            Text("Search above to add one: a city, an airport code like SFO, or a time zone like PST.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
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
        case "add": query = "san"
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
            if !store.places.isEmpty { TimeShifter() }
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

}

/// Moves every city through time from the header: a slider from 12 hours back to 12 ahead (in
/// quarter-hours, "Now" in the middle), one-tap −3/−1/Now/+1/+3 hours, and 123 to type an offset
/// ("+3", "-1.5", "-2:30"). The date picker in the header goes further; the day bars still drag.
private struct TimeShifter: View {
    @EnvironmentObject private var store: CityStore
    @State private var typing = false
    @State private var typed = ""
    @State private var invalid = false

    private static let range = 12.0
    private static let presets = [-3, -1, 0, 1, 3]

    /// Hours from now, as the slider shows them (clamped to its range).
    private var hours: Binding<Double> {
        Binding(
            get: { min(max(Double(store.offsetMinutes) / 60, -Self.range), Self.range) },
            set: { store.scrub(to: Int(($0 * 4).rounded()) * 15) }
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: hours, in: -Self.range...Self.range, step: 0.25) {
                Text("Hours from now")
            } minimumValueLabel: {
                Text("−12 hr").font(.caption2).foregroundStyle(Theme.faint)
            } maximumValueLabel: {
                Text("+12 hr").font(.caption2).foregroundStyle(Theme.faint)
            }
            // No fill: Now is in the middle, so a half-filled track would read as "halfway".
            .tint(Theme.border)
            .accessibilityValue(store.isNow ? "Now" : Self.describe(store.offsetMinutes))
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    let on = store.offsetMinutes == preset * 60
                    Button {
                        if preset == 0 { store.backToNow() } else { store.shift(minutes: preset * 60) }
                    } label: {
                        Text(preset == 0 ? "Now" : "\(preset > 0 ? "+" : "−")\(abs(preset)) hr")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Capsule().fill(on ? Theme.cream : Theme.tile))
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: on ? 0 : 0.5).allowsHitTesting(false))
                            .foregroundStyle(on ? Theme.bg : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset == 0 ? "Now" : "\(abs(preset)) \(abs(preset) == 1 ? "hour" : "hours") \(preset > 0 ? "from now" : "ago")")
                }
                Button { typed = ""; invalid = false; typing = true } label: {
                    Text("123")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 40, height: 32)
                        .background(Capsule().fill(Theme.tile))
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5).allowsHitTesting(false))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Type hours from now")
            }
        }
        .alert("Hours from now", isPresented: $typing) {
            TextField("+3, -1.5 or -2:30", text: $typed)
                .keyboardType(.numbersAndPunctuation)
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                if let minutes = Self.parse(typed) {
                    store.shift(minutes: minutes)
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

    /// "+3", "3", "-1.5", "−2:30", "+0:45 hr" -> minutes from now (up to a week either way).
    static func parse(_ text: String) -> Int? {
        var t = text.lowercased().replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "hours", with: "").replacingOccurrences(of: "hour", with: "")
            .replacingOccurrences(of: "hrs", with: "").replacingOccurrences(of: "hr", with: "")
            .replacingOccurrences(of: "h", with: "").replacingOccurrences(of: " ", with: "")
        var sign = 1
        if t.hasPrefix("-") { sign = -1; t.removeFirst() } else if t.hasPrefix("+") { t.removeFirst() }
        let minutes: Double
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = Double(parts[0].isEmpty ? "0" : String(parts[0])), let m = Double(parts[1]), m < 60 else { return nil }
            minutes = h * 60 + m
        } else {
            guard let h = Double(t.replacingOccurrences(of: ",", with: ".")) else { return nil }
            minutes = h * 60
        }
        guard minutes <= 7 * 24 * 60 else { return nil }
        return sign * Int(minutes.rounded())
    }

    static func describe(_ minutes: Int) -> String {
        let a = abs(minutes), h = a / 60, m = a % 60
        let span = [h > 0 ? "\(h) \(h == 1 ? "hour" : "hours")" : nil, m > 0 ? "\(m) minutes" : nil].compactMap { $0 }.joined(separator: " ")
        return minutes > 0 ? "\(span) from now" : "\(span) ago"
    }
}

/// One city, in the manner of Apple's Clock: how it relates to you and its name on the left, its
/// time large and light on the right; then a slim day-and-night bar of its hours.
struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 40
    let place: Place
    /// In Edit List: a compact row (name, offset, time) so the delete button and handle fit.
    var editing = false

    /// "My Location" on the card for where you are; with the city you're in when this card is
    /// another city in the same time zone ("My Location · Boulder" on Denver).
    private var hereLabel: String? {
        guard store.isHere(place) else { return nil }
        if !place.isMyLocation, let city = store.hereCity, city != place.name { return "My Location · \(city)" }
        return "My Location"
    }

    /// Outside working hours at the selected moment (when that setting is on).
    private var outsideWorkHours: Bool {
        store.showWorkHours && !store.isWorking(place, at: store.moment)
    }

    var body: some View {
        if editing { compactRow } else { fullRow }
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(place.name).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                    if store.isHere(place) { Image(systemName: "location.fill").font(.caption2).foregroundStyle(Theme.cream) }
                }
                Text(detail(store.moment)).font(.footnote).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeMath.time(store.moment, in: place.timeZone, use24h: store.use24h))
                .font(.body).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var fullRow: some View {
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
                    Text(place.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    // Where you are, on this card rather than a second card for the same place.
                    if let here = hereLabel {
                        Label(here, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.cream)
                            .labelStyle(.titleAndIcon)
                            .padding(.top, 2)
                    }
                    // This city's own note, rather than a list of names in the header.
                    if outsideWorkHours {
                        Label("Outside work hours", systemImage: "moon.zzz.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .labelStyle(.titleAndIcon)
                            .padding(.top, 2)
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
        .accessibilityLabel("\(place.name)\(hereLabel.map { ", \($0)" } ?? ""), \(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h)), \(detail(moment))\(outsideWorkHours ? ", outside work hours" : "")")
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
                    let dim = store.showWorkHours && !store.isWorking(place, at: at)
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

/// One search result: the city and its region; its time and offset; added or not.
private struct SearchResultRow: View {
    @EnvironmentObject private var store: CityStore
    let entry: CityEntry
    let added: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                Text(entry.region.replacingOccurrences(of: "_", with: " "))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let zone = TimeZone(identifier: entry.timeZoneID) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeMath.time(store.now, in: zone, use24h: store.use24h))
                        .foregroundStyle(Theme.secondary).monospacedDigit()
                    Text(TimeMath.offsetLabel(seconds: zone.secondsFromGMT(for: store.now)))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            Image(systemName: added ? "checkmark" : "plus.circle.fill")
                .foregroundStyle(added ? Theme.faint : Theme.cream)
        }
        .contentShape(Rectangle())
    }
}
