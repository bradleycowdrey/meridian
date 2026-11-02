import SwiftUI

/// The whole app on one screen: the moment you're looking at, one row per city (its time, large,
/// over a slim day-and-night bar of its hours). Drag any bar sideways to move through time in
/// quarter-hours; tap the date to jump to any day.
struct ContentView: View {
    @EnvironmentObject private var store: CityStore
    /// Search to add a city, right above the cards (as in Apple's Weather and Two Degrees).
    @State private var query = ""
    /// + in the top bar: the search field shows (and the keyboard) until a city is added or ✓.
    @State private var adding = false
    @FocusState private var searchFocused: Bool
    /// Edit List (the pencil): reorder and remove in place, then ✓.
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
    @State private var showingFind = false
    /// "Add a Person Here": the card the person is in the city of, and their name.
    @State private var personFor: Place?
    @State private var personName = ""
    /// The card whose groups are being chosen.
    @State private var groupsFor: Place?

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
            .sheet(isPresented: $showingFind) { FindTimeView() }
            .sheet(item: $groupsFor) { place in GroupsView(place: place) }
            .alert("Add a Person in \(personFor?.isMyLocation == true ? (store.hereCity ?? "My Location") : personFor?.name ?? "")", isPresented: isAddingPerson) {
                TextField("Name", text: $personName).textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { personFor = nil }
                Button("Add") { if let p = personFor { store.addPerson(personName, at: p) }; personFor = nil }
            } message: {
                Text("Their card shows their name, with the city's time, working hours and holidays.")
            }
            // A tick per quarter-hour, a firmer one on each whole hour; only for the user's own moves.
            .sensoryFeedback(trigger: store.userMoves) { _, _ in haptic }
            .alert(renaming?.person != nil ? "Rename Person" : "Rename City", isPresented: isRenaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { finishRename() }
            }
            .confirmationDialog(actionsFor?.title ?? "", isPresented: showingActions, titleVisibility: .visible, presenting: actionsFor) { place in
                Button("Copy Time") { copy(place) }
                Button("Working Days & Hours") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { workFor = place }
                }
                if store.canAdd {
                    Button("Add a Person Here") { later { personName = ""; personFor = place } }
                }
                Button(place.groups == nil ? "Add to a Group" : "Groups") { later { groupsFor = place } }
                if !place.isMyLocation || place.person != nil {
                    Button("Rename") {
                        newName = place.title
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

    /// After the dialog has gone, so the next alert or sheet can show.
    private func later(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private var isAddingPerson: Binding<Bool> {
        Binding(get: { personFor != nil }, set: { if !$0 { personFor = nil } })
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
            .environment(\.editMode, $editMode)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    private var cityList: some View {
        List {
            if adding {
                searchField
                if !query.trimmingCharacters(in: .whitespaces).isEmpty { searchResults } else { searchHint }
            } else {
                cards
            }
        }
    }

    /// The search field, shown by + in the top bar.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField("City, SFO, PST, UTC+5", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { if let first = CityDirectory.search(query).first(where: { !store.contains($0) }) { add(first) } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.tile))
        .listRowInsets(EdgeInsets(top: 12, leading: Card.margin, bottom: 8, trailing: Card.margin))
        .listRowBackground(Theme.bg)
        .listRowSeparator(.hidden)
    }

    private var searchHint: some View {
        Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30.")
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .listRowBackground(Theme.bg)
            .listRowSeparator(.hidden)
    }

    private func add(_ entry: CityEntry) {
        store.add(entry)
        closeSearch()
    }

    private func closeSearch() {
        query = ""
        searchFocused = false
        withAnimation(.snappy) { adding = false }
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
                add(entry)
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
            if !editMode.isEditing {
                if !store.groups.isEmpty { groupFilter }
                ForEach(store.clockChanges) { change in clockNotice(change) }
            }
            // In Edit List every card shows, so removing and moving follow the full list.
            ForEach(editMode.isEditing ? store.places : store.visiblePlaces) { place in
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
            MomentHeader(copied: copied, editing: editMode.isEditing)
                .padding(.horizontal, Card.margin).padding(.top, 6).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg)
                .listRowInsets(EdgeInsets())
                .textCase(nil)
        }
    }

    /// Everyone, or one group: chips above the cards.
    private var groupFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Everyone", on: store.groupFilter == nil) { store.groupFilter = nil }
                ForEach(store.groups, id: \.self) { group in
                    filterChip(group, on: store.groupFilter == group) { store.groupFilter = group }
                }
            }
            .padding(.horizontal, Card.margin)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Theme.bg)
        .listRowSeparator(.hidden)
    }

    private func filterChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 32)
                .background(Capsule().fill(on ? Theme.cream : Theme.tile))
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5).allowsHitTesting(false))
                .foregroundStyle(on ? Theme.bg : Theme.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A city's clocks change soon: when, and how far it will be from you afterwards.
    private func clockNotice(_ change: ClockChange) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.cream)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.headline(use24h: store.use24h))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                if let detail = change.detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { store.dismiss(change) } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.faint)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .listRowInsets(EdgeInsets(top: Card.gap / 2 + 14, leading: Card.margin + 14, bottom: Card.gap / 2 + 14, trailing: Card.margin + 8))
        .listRowBackground(
            RoundedRectangle(cornerRadius: Card.radius, style: .continuous)
                .fill(Theme.crimson.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).strokeBorder(Theme.crimson.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, Card.margin)
                .padding(.vertical, Card.gap / 2)
        )
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private func row(_ place: Place) -> some View {
        // Each city is a card: 16 pt from the screen edges, 16 pt inside, 12 pt between cards
        // (Apple's standard margins; continuous corners like the system's own cards), with a
        // hairline edge so cards stand apart on the dark background. Each card has its own
        // actions: touch and hold for the menu (a tap does nothing). No swipe to remove: a sideways
        // swipe drags the day bar, which moves the time for every city.
        CityRow(place: place, editing: editMode.isEditing)
            .contentShape(Rectangle())
            .deleteDisabled(!editMode.isEditing)
            .moveDisabled(!editMode.isEditing)
            .listRowInsets(EdgeInsets(top: Card.gap / 2 + Card.padding, leading: Card.margin + Card.padding,
                                      bottom: Card.gap / 2 + Card.padding, trailing: Card.margin + Card.padding))
            .listRowBackground(
                RoundedRectangle(cornerRadius: Card.radius, style: .continuous)
                    .fill(editMode.isEditing ? AnyShapeStyle(Theme.tile) : AnyShapeStyle(CardSky.gradient(for: place, at: store.moment)))
                    .animation(.easeInOut(duration: 0.6), value: CardSky.phase(for: place, at: store.moment))
                    .overlay(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
                    .padding(.horizontal, Card.margin)
                    .padding(.vertical, Card.gap / 2)
            )
            .listRowSeparator(.hidden)
            .contextMenu {
                Button { copy(place) } label: { Label("Copy Time", systemImage: "doc.on.doc") }
                Button { workFor = place } label: { Label("Working Days & Hours", systemImage: "briefcase") }
                Button { personName = ""; personFor = place } label: { Label("Add a Person Here", systemImage: "person.badge.plus") }
                    .disabled(!store.canAdd)
                Button { groupsFor = place } label: { Label("Groups", systemImage: "person.3") }
                if !place.isMyLocation || place.person != nil {
                    Button { newName = place.title; renaming = place } label: { Label("Rename", systemImage: "pencil") }
                }
                Button(role: .destructive) {
                    store.remove(place)
                } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityAction(named: "Copy Time") { copy(place) }
            .accessibilityAction(named: "Rename") { if !place.isMyLocation || place.person != nil { newName = place.title; renaming = place } }
            .accessibilityAction(named: "Remove") { store.remove(place) }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { shareMenu }
        ToolbarItemGroup(placement: .topBarTrailing) {
            listControls
            Menu {
                Button { showingFind = true } label: { Label("Find a Time…", systemImage: "person.2.badge.gearshape") }
                    .disabled(store.places.isEmpty)
                Button { showingDate = true } label: { Label("Go to a Time…", systemImage: "calendar") }
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

    /// + and the pencil in one capsule, as in Two Degrees and Meridian for Mac: + shows the search
    /// field, the pencil turns on Edit List; whichever is on shows ✓ to finish.
    private var listControls: some View {
        HStack(spacing: 0) {
            controlButton(symbol: adding ? "checkmark" : "plus", on: adding,
                          label: adding ? "Done Adding" : "Add a City", enabled: store.canAdd || adding) {
                if adding { closeSearch() } else {
                    withAnimation(.snappy) { editMode = .inactive; adding = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { searchFocused = true }
                }
            }
            Theme.border.frame(width: 0.5, height: 14).opacity(adding || editMode.isEditing ? 0 : 1)
            controlButton(symbol: editMode.isEditing ? "checkmark" : "pencil", on: editMode.isEditing,
                          label: editMode.isEditing ? "Done Editing" : "Edit List", enabled: !store.places.isEmpty || editMode.isEditing) {
                if adding { closeSearch() }
                withAnimation(.snappy) { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.tile))
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5).allowsHitTesting(false))
    }

    private func controlButton(symbol: String, on: Bool, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 28)
                .background(Capsule().fill(on ? Theme.cream : .clear))
                .foregroundStyle(on ? Theme.bg : (enabled ? Theme.secondary : Theme.faint))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
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
            Text("Tap + at the top to add one: a city, an airport code like SFO, or a time zone like PST.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com\u{00A0}↗", destination: Theme.website)
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
        case "add": adding = true; query = "san"
        case "settings": showingSettings = true
        case "date": showingDate = true
        case "find": showingFind = true
        case "edit": editMode = .active
        case "travel": store.jump(to: TimeMath.hourAnchor(store.now).addingTimeInterval(5 * 3600), animated: false)
        default: break
        }
    }

    private func copy(_ place: Place) {
        UIPasteboard.general.string = "\(place.title): \(TimeMath.fullMoment(store.moment, in: place.timeZone, use24h: store.use24h))"
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
    let copied: Bool
    /// In Edit List the time controls step aside.
    var editing = false

    /// The ruler and the hour buttons, nothing more: the "Your time" card already shows the time
    /// (and its date, when that's another day). "Copied" shows briefly after copying.
    var body: some View {
        VStack(spacing: 8) {
            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.tile))
                    .foregroundStyle(Theme.cream)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !store.places.isEmpty && !editing { TimeShifter() }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: copied)
    }

}

/// Moves every city through time from the header: a slider from 12 hours back to 12 ahead (in
/// quarter-hours, "Now" in the middle), one-tap −2/−1/Now/+1/+2 hours, and 123 to type an offset
/// ("+3", "-1.5", "-2:30"). The date picker in the header goes further; the day bars still drag.
struct TimeShifter: View {
    @EnvironmentObject private var store: CityStore

    private static let presets = [-2, -1, 0, 1, 2]

    var body: some View {
        VStack(spacing: 8) {
            TimeRuler()
            // −2 · −1 · Now · +1 · +2: Now in the middle, wider, and always easy to find: solid when
            // you've moved away (come back), outlined with the red dot when you're there.
            HStack(alignment: .center, spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    if preset == 0 { nowButton } else { hourButton(preset) }
                }
            }
        }
    }

    private var nowButton: some View {
        Button { store.backToNow() } label: {
            HStack(spacing: 6) {
                if store.isNow { Circle().fill(Theme.crimson).frame(width: 6, height: 6) }
                Text("Now").font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(store.isNow ? Theme.tile : Theme.cream))
            .overlay(Capsule().strokeBorder(Theme.cream, lineWidth: store.isNow ? 1.5 : 0).allowsHitTesting(false))
            .foregroundStyle(store.isNow ? Theme.cream : Theme.bg)
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .frame(minWidth: 100)
        .accessibilityLabel(store.isNow ? "Now" : "Back to now")
    }

    private func hourButton(_ preset: Int) -> some View {
        let on = store.offsetMinutes == preset * 60
        return Button { store.shift(minutes: preset * 60) } label: {
            Text("\(preset > 0 ? "+" : "−")\(abs(preset)) hr")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(on ? Theme.secondary : Theme.tile))
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: on ? 0 : 0.5).allowsHitTesting(false))
                .foregroundStyle(on ? Theme.bg : Theme.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(abs(preset)) \(abs(preset) == 1 ? "hour" : "hours") \(preset > 0 ? "from now" : "ago")")
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

/// The time ruler: the day as a strip of hours and quarter-hours under a fixed line, as in the
/// camera's zoom dial. Swipe or flick it and it settles on a quarter-hour of the clock (:00, :15,
/// :30, :45), ticking as it passes each one; tap an hour to go there. Two days either way; the date
/// in the header goes further.
private struct TimeRuler: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The quarter-hour under the line, as an index (quarter-hours since 2001).
    @State private var position: Int?

    private static let tick: CGFloat = 14
    private static let span = 4 * 48

    private static func index(_ date: Date, rounded rule: FloatingPointRoundingRule) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 900).rounded(rule))
    }
    private static func date(_ index: Int) -> Date { Date(timeIntervalSinceReferenceDate: Double(index) * 900) }

    /// The quarter-hour that stands for now (the one just begun).
    private var nowIndex: Int { Self.index(store.now, rounded: .down) }
    private var selectedIndex: Int { store.isNow ? nowIndex : Self.index(store.moment, rounded: .toNearestOrAwayFromZero) }

    var body: some View {
        let center = nowIndex
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach((center - Self.span)...(center + Self.span), id: \.self) { i in
                        RulerTick(date: Self.date(i), isNow: i == center, use24h: store.use24h)
                            .frame(width: Self.tick, height: 56)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy) { position = i } }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - Self.tick) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
        }
        .frame(height: 56)
        // The fixed line: where you are in time.
        .overlay {
            VStack(spacing: 0) {
                Capsule().fill(Theme.cream).frame(width: 3, height: 34)
                Spacer(minLength: 0)
            }
            .padding(.top, 22)
            .allowsHitTesting(false)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .onAppear { position = selectedIndex }
        .onChange(of: position) { _, new in
            guard let new, new != selectedIndex else { return }
            if new == nowIndex { store.backToNow() } else { store.scrub(toQuarter: Self.date(new)) }
        }
        .onChange(of: selectedIndex) { _, new in
            guard position != new else { return }
            if reduceMotion { position = new } else { withAnimation(.snappy) { position = new } }
        }
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(store.isNow ? "Now" : TimeShifter.describe(store.offsetMinutes))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            store.scrub(toQuarter: Self.date(selectedIndex + step))
        }
    }
}

/// One quarter-hour on the ruler: a tall tick and its hour on the hour ("9 AM", or the day at
/// midnight), a shorter one at the half-hour, a short one at the quarters.
private struct RulerTick: View {
    let date: Date
    let isNow: Bool
    let use24h: Bool

    var body: some View {
        let parts = Calendar.current.dateComponents([.hour, .minute, .weekday], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        VStack(spacing: 4) {
            Group {
                if minute == 0 {
                    Text(label(hour: hour, weekday: parts.weekday ?? 1))
                        .font(.caption2.weight(hour == 0 ? .bold : .medium))
                        .foregroundStyle(hour == 0 ? Theme.cream : Theme.muted)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Text(" ").font(.caption2)
                }
            }
            .frame(height: 14)
            Capsule()
                .fill(minute == 0 ? Theme.secondary : Theme.faint)
                .frame(width: minute == 0 ? 2 : 1.5, height: minute == 0 ? 20 : (minute == 30 ? 13 : 8))
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func label(hour: Int, weekday: Int) -> String {
        if hour == 0 { return Calendar(identifier: .gregorian).shortWeekdaySymbols[weekday - 1].uppercased() }
        if use24h { return String(format: "%02d", hour) }
        return "\(hour % 12 == 0 ? 12 : hour % 12)\u{2009}\(hour < 12 ? "AM" : "PM")"
    }
}

/// One city, in the manner of Apple's Clock: how it relates to you and its name on the left, its
/// time large and light on the right; then a slim day-and-night bar of its hours.
/// A status: a small icon and its words, close together.
struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var statusHeight: CGFloat = 20
    let place: Place
    /// In Edit List: a compact row (name, offset, time) so the delete button and handle fit.
    var editing = false

    /// "My Location" on the card for where you are; with the city you're in when this card is
    /// another city in the same time zone ("My Location · Boulder" on Denver).
    private var hereLabel: String? {
        guard store.isHere(place) else { return nil }
        if !place.isMyLocation, place.person == nil, let city = store.hereCity, city != place.name { return "My Location · \(city)" }
        return "My Location"
    }

    /// "Off hours", "Weekend" or "Day off" when the city isn't at work (and that setting is on).
    private var offLabel: String? {
        store.showWorkHours ? WorkWeek.offLabel(place, at: store.moment, start: store.workStart, end: store.workEnd) : nil
    }

    /// "Working" with a briefcase, or "Off hours", "Weekend", "Day off" with a moon (when that
    /// setting is on).
    private var workStatus: (text: String, icon: String, working: Bool)? {
        guard store.showWorkHours else { return nil }
        if let off = offLabel { return (off, "moon.zzz.fill", false) }
        return ("Working", "briefcase.fill", true)
    }

    /// "Sets 4:59 PM" while the sun is up there, "Rises 6:27 AM" while it's down.
    private var sunStatus: (text: String, icon: String)? {
        let time = { (date: Date) in TimeMath.time(date, in: place.timeZone, use24h: store.use24h) }
        switch Sun.phase(zoneID: place.timeZoneID, at: store.moment) {
        case .day(let sets)?: return ("Sets \(time(sets))", "sun.max.fill")
        case .night(let rises)?: return ("Rises \(time(rises))", "sunrise.fill")
        case .allDay?: return ("Sun all day", "sun.max.fill")
        case .allNight?: return ("Polar night", "moon.stars.fill")
        case nil: return nil
        }
    }

    var body: some View {
        if editing { compactRow } else { fullRow }
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(place.title).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
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
        VStack(alignment: .leading, spacing: 10) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail(moment))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        Text(place.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .minimumScaleFactor(0.8)
                        // Where you are, on this card rather than a second card for the same place.
                        if hereLabel != nil {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.cream)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                // The time is never cut short: the name gives way first.
                clock(hour: hour, minute: minute)
                    .fixedSize()
                    .layoutPriority(1)
            }
            // One status line on every card, always there (so every card is the same height) and
            // apart from the time (so it never squeezes or moves it): the day, work, the sun.
            HStack(spacing: 14) {
                // "+1 d" / "−1 d" when the city is on another day, as in the Mac app and widgets.
                let shift = TimeMath.dayShift(moment, zone: place.timeZone)
                if shift != 0 {
                    Text(shift > 0 ? "+\(shift) d" : "−\(-shift) d")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.border))
                        .foregroundStyle(Theme.cream)
                        .fixedSize()
                }
                if let work = workStatus {
                    Label(work.text, systemImage: work.icon)
                        .foregroundStyle(work.working ? Theme.secondary : Theme.muted)
                }
                if let sun = sunStatus {
                    Label(sun.text, systemImage: sun.icon)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .labelStyle(StatusLabelStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minHeight: statusHeight)
            DayBar(place: place)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([place.title, place.person != nil ? place.name : nil, hereLabel, TimeMath.time(moment, in: place.timeZone, use24h: store.use24h),
                             detail(moment), dayNote(moment), workStatus?.text, sunStatus.map { "sun \($0.text.lowercased())" }]
                             .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
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
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// "+8 hr · UTC+1", "+5:30 hr · UTC+5:30", "Your time · UTC−7".
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// ", tomorrow there" for VoiceOver.
    private func dayNote(_ moment: Date) -> String {
        switch TimeMath.dayShift(moment, zone: place.timeZone) {
        case 0: return ""
        case 1: return "tomorrow there"
        case -1: return "yesterday there"
        case let d: return "\(abs(d)) days \(d > 0 ? "ahead" : "behind")"
        }
    }

    /// "My Location · UTC−7" on the card for where you are, else how the city relates to you.
    private func detail(_ moment: Date) -> String {
        // A person's card names their city first: "Lisbon · +8 hr · UTC+1".
        let base = (place.person != nil ? "\(place.name) · " : "") + relation(moment)
        guard let here = hereLabel else { return base }
        return here + " · " + (base.hasPrefix("Your time · ") || base.hasPrefix("Same time · ") ? String(base.split(separator: "·").last!).trimmingCharacters(in: .whitespaces) : base)
    }

    private func relation(_ moment: Date) -> String {
        let utc = place.offsetLabel(at: moment)
        let diff = place.timeZone.secondsFromGMT(for: moment) - TimeZone.current.secondsFromGMT(for: moment)
        if diff == 0 {
            // Your own city on another day (a date you went to) shows that date instead.
            if place.timeZone.identifier == TimeZone.current.identifier, !Calendar.current.isDate(moment, inSameDayAs: store.now) {
                return "\(Self.day.string(from: moment)) · \(utc)"
            }
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
                    store.scrub(toQuarterNear: Double(start) + minutes)
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
                Text(WorkWeek.countryName(zoneID: entry.timeZoneID) ?? entry.region.replacingOccurrences(of: "_", with: " "))
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

/// The groups a card is in ("Design team", "Family"): tick existing ones or make a new one.
struct GroupsView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    let place: Place
    @State private var chosen: Set<String> = []
    @State private var newGroup = ""

    var body: some View {
        NavigationStack {
            Form {
                if !allGroups.isEmpty {
                    Section {
                        ForEach(allGroups, id: \.self) { group in
                            Button {
                                if chosen.contains(group) { chosen.remove(group) } else { chosen.insert(group) }
                            } label: {
                                HStack {
                                    Text(group).foregroundStyle(Theme.primary)
                                    Spacer()
                                    if chosen.contains(group) { Image(systemName: "checkmark").foregroundStyle(Theme.cream) }
                                }
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("New group, like Design Team", text: $newGroup)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addNew)
                        Button("Add", action: addNew).disabled(newGroup.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Show one group at a time on your list, and pick a group in Find a Time.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(place.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.setGroups(Array(chosen), for: place); dismiss() }
                }
            }
            .onAppear { chosen = Set(place.groups ?? []) }
        }
        .tint(Theme.cream)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var allGroups: [String] { Array(Set(store.groups).union(chosen)).sorted() }

    private func addNew() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        chosen.insert(String(name.prefix(30)))
        newGroup = ""
    }
}
