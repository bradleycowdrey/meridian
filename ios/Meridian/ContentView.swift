import SwiftUI

/// The whole app on one screen: one card per city (its time, large, over a row of five hour tiles
/// shaded for day and night), with the column labels pinned above and the time ruler below. Drag
/// any row of tiles sideways to move through time in quarter-hours; tap a tile to go to that hour.
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
    @State private var groupPickerFor: Place?
    /// Groups: the list, one group, or a new one.
    @State private var groupsRoute: GroupsRoute?

    var body: some View {
        NavigationStack {
            screen
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    // The body is split into parts so the Swift compiler can type-check each one quickly.

    private var screen: some View {
        styledList
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDate) { DateJumpView() }
            .sheet(isPresented: $showingFind) { FindTimeView() }
            .sheet(item: $groupPickerFor) { place in GroupPicker(placeID: place.id) }
            .sheet(item: $groupsRoute) { route in GroupsSheet(route: route) }
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
                Button("Groups\u{2026}") { later { groupPickerFor = place } }
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
                    .meridianForm()
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
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Meridian")
            // The title sits small in the bar, between Share and the + and pencil; never large.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.editMode, $editMode)
            // The groups and the column labels pinned at the top, over the tiles they label.
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            // The time ruler and Now on a frosted bar at the bottom, in thumb reach, as Two Degrees' bar.
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    /// The bars, while the cards show (not while adding a city or editing the list).
    private var showBar: Bool { !adding && !editMode.isEditing && !store.places.isEmpty }
    /// The group chips: once there's a group to pick (a custom one, or two continents).
    private var showGroupBar: Bool { showBar && (!store.customGroups.isEmpty || store.continentChipCount >= 2) }
    /// The column labels: while there are cards under them.
    private var showHeader: Bool { showBar && !store.visiblePlaces.isEmpty }

    @ViewBuilder private var topBar: some View {
        if showGroupBar || showHeader {
            VStack(spacing: 0) {
                if showGroupBar {
                    GroupBar(open: { groupsRoute = $0 }, openSettings: { showingSettings = true })
                }
                if showHeader { ColumnHeader() }
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(Theme.Op.track)).frame(height: 0.5)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if copied {
                CopiedPill()
                    .padding(.bottom, showBar ? 0 : 8)
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.9)))
            }
            if showBar {
                TimeShifter(goToTime: { showingDate = true })
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
                    .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(Theme.Op.track)) }
                    .environment(\.colorScheme, .dark)
            }
        }
        .animation(.snappy, value: copied)
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
            Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(Theme.Op.caption))
            TextField("City, SFO, PST, UTC+5", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { if let first = CityDirectory.search(query).first(where: { !store.contains($0) }) { add(first) } }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.white.opacity(Theme.Op.caption))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(Theme.Op.fill)))
        .listRowInsets(EdgeInsets(top: 4, leading: Card.margin, bottom: 8, trailing: Card.margin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var searchHint: some View {
        Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30." + addingTo)
            .font(.system(size: 15))
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// " Adding to Design Team." while a custom group is showing.
    private var addingTo: String {
        guard let f = store.groupFilter, store.customGroups.contains(f) else { return "" }
        return " Adding to \(f)."
    }

    private func add(_ entry: CityEntry) {
        let id = store.add(entry)
        // While a group shows, a new city joins it (a custom group); or, if it's on another
        // continent, the list goes back to every city so the new card doesn't vanish.
        if let id, let f = store.groupFilter, let p = store.places.first(where: { $0.id == id }) {
            if !store.isContinent(f) {
                store.setGroups((p.groups ?? []) + [f], for: p)
            } else if !store.groups(of: p).contains(f) {
                withAnimation(.snappy) { store.groupFilter = nil }
            }
        }
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
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        let results = CityDirectory.search(query)
        if results.isEmpty {
            Text("No places match “\(query)”. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        ForEach(results) { entry in
            let added = store.contains(entry)
            Button {
                add(entry)
            } label: {
                SearchResultRow(entry: entry, added: added)
            }
            .disabled(added || !store.canAdd)
            .listRowInsets(EdgeInsets(top: 10, leading: Card.margin, bottom: 10, trailing: Card.margin))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.white.opacity(Theme.Op.track))
            .accessibilityHint(added ? "Already added" : "Adds \(entry.name)")
        }
    }

    @ViewBuilder private var cards: some View {
        if store.places.isEmpty {
            emptyState
        }
        if !editMode.isEditing {
            ForEach(store.clockChanges) { change in clockNotice(change) }
            if !store.places.isEmpty && store.visiblePlaces.isEmpty, let f = store.groupFilter {
                emptyGroup(f)
            }
        }
        // In Edit List every card shows, so removing and moving follow the full list.
        ForEach(editMode.isEditing ? store.places : store.visiblePlaces) { place in
            row(place)
        }
        // Remove and reorder in Edit List only: a sideways swipe on a card drags its hour tiles.
        .onDelete { store.remove(at: $0) }
        .onMove { store.move(from: $0, to: $1) }
        // The last row, not a section footer: a plain list pins footers to the bottom of the screen.
        footer
            .listRowInsets(EdgeInsets(top: 8, leading: Card.margin, bottom: 24, trailing: Card.margin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The group showing has no cities yet: add some, or show every city.
    private func emptyGroup(_ group: String) -> some View {
        VStack(spacing: 14) {
            Text("No cities in \(group) yet.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { groupsRoute = .detail(group) } label: {
                    Text("Add Cities")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(Capsule().fill(Color.white))
                        .foregroundStyle(Color.black)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { withAnimation(.snappy) { store.groupFilter = nil } } label: {
                    Text("Show All")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(Theme.Op.fill)))
                        .foregroundStyle(Color.white)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// A city's clocks change soon: when, and how far it will be from you afterwards.
    private func clockNotice(_ change: ClockChange) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.notice)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.headline(use24h: store.use24h))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                if let detail = change.detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { store.dismiss(change) } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                    .frame(width: 44, height: 44).contentShape(Rectangle()).padding(-11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(Card.padding)
        .background(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).fill(Theme.notice.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: Card.radius, style: .continuous).strokeBorder(Theme.notice.opacity(0.7), lineWidth: 1))
        .listRowInsets(EdgeInsets(top: Card.gap / 2, leading: Card.margin, bottom: Card.gap / 2, trailing: Card.margin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private func row(_ place: Place) -> some View {
        // Each city is a card on its own sky, as in Two Degrees: 16 pt from the screen edges, 14 pt
        // inside, 10 pt between cards, continuous corners. Each card has its own actions: touch and
        // hold for the menu (a tap does nothing). No swipe to remove: a sideways swipe drags the hour
        // tiles, which moves the time for every city.
        let shape = RoundedRectangle(cornerRadius: Card.radius, style: .continuous)
        return CityRow(place: place, editing: editMode.isEditing)
            .padding(Card.padding)
            .background { SkyView(phase: Sky.phase(for: place, at: store.moment)) }
            .clipShape(shape)
            .overlay {
                // Where you are, as Two Degrees outlines its chosen city.
                if store.isHere(place) {
                    shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5).allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .contentShape(.contextMenuPreview, shape)
            .deleteDisabled(!editMode.isEditing)
            .moveDisabled(!editMode.isEditing)
            .listRowInsets(EdgeInsets(top: Card.gap / 2, leading: Card.margin, bottom: Card.gap / 2, trailing: Card.margin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contextMenu {
                Button { copy(place) } label: { Label("Copy Time", systemImage: "doc.on.doc") }
                Button { workFor = place } label: { Label("Working Days & Hours", systemImage: "briefcase") }
                Button { personName = ""; personFor = place } label: { Label("Add a Person Here", systemImage: "person.badge.plus") }
                    .disabled(!store.canAdd)
                Button { groupPickerFor = place } label: { Label("Groups\u{2026}", systemImage: "square.stack") }
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
        ToolbarItem(placement: .principal) {
            Text("Meridian")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            listControls
            Menu {
                Button { showingFind = true } label: { Label("Find a Time…", systemImage: "person.2.badge.gearshape") }
                    .disabled(store.places.isEmpty)
                Button { showingDate = true } label: { Label("Go to a Time…", systemImage: "calendar") }
                Button { groupsRoute = .manage } label: { Label("Groups\u{2026}", systemImage: "square.stack") }
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
                Image(systemName: "ellipsis.circle").font(.system(size: 19))
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
            Color.white.opacity(Theme.Op.track).frame(width: 0.5, height: 14).opacity(adding || editMode.isEditing ? 0 : 1)
            controlButton(symbol: editMode.isEditing ? "checkmark" : "pencil", on: editMode.isEditing,
                          label: editMode.isEditing ? "Done Editing" : "Edit List", enabled: !store.places.isEmpty || editMode.isEditing) {
                if adding { closeSearch() }
                withAnimation(.snappy) { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(Theme.Op.fill)))
    }

    private func controlButton(symbol: String, on: Bool, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 28)
                .background(Capsule().fill(on ? Color.white : .clear))
                .foregroundStyle(on ? Color.black : Color.white.opacity(enabled ? 1 : Theme.Op.faint))
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
            Text("No cities yet").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
            Text("Tap + at the top to add one: a city, an airport code like SFO, or a time zone like PST.")
                .font(.system(size: 15)).foregroundStyle(Color.white.opacity(Theme.Op.caption)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// As Two Degrees' footer: small, centred, quiet.
    private var footer: some View {
        VStack(spacing: 6) {
            Link("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com\u{00A0}↗", destination: Theme.website)
            Link("Terms & Privacy", destination: Theme.legal)
        }
        .font(.system(size: 13))
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
        .tint(Color.white.opacity(Theme.Op.caption))
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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

/// "Copied", briefly, after copying a time, a link or a message.
private struct CopiedPill: View {
    var body: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

/// Moves every city through time from the bottom bar, in one row within thumb reach: Go to a Time
/// (the calendar), a ruler from two days back to two ahead (in quarter-hours, under a fixed line),
/// and Now. The column labels above the cards jump an hour at a time; the tiles drag.
struct TimeShifter: View {
    @EnvironmentObject private var store: CityStore
    let goToTime: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if !store.hasScrubbed {
                Text("Drag the hours or the ruler to change the time.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            HStack(spacing: 8) {
                Button(action: goToTime) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to a Time")
                TimeRuler()
                    .frame(maxWidth: .infinity)
                nowButton
            }
            .padding(.horizontal, 12)
        }
    }

    private var nowButton: some View {
        Button { store.backToNow() } label: {
            Text("Now")
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .frame(width: 64, height: 32)
                .background(Capsule().fill(store.isNow ? Color.white.opacity(Theme.Op.fill) : Color.white))
                .foregroundStyle(store.isNow ? Color.white.opacity(Theme.Op.faint) : Color.black)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isNow)
        .accessibilityLabel(store.isNow ? "Now" : "Back to now")
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
                            .frame(width: Self.tick, height: 40)
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
        .frame(height: 40)
        // The fixed line: where you are in time.
        .overlay {
            VStack(spacing: 0) {
                Capsule().fill(Color.white).frame(width: 2, height: 24)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
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
        VStack(spacing: 3) {
            Group {
                if minute == 0 {
                    Text(label(hour: hour, weekday: parts.weekday ?? 1))
                        .font(.system(size: 11, weight: hour == 0 ? .semibold : .medium))
                        .foregroundStyle(Color.white.opacity(hour == 0 ? 1 : Theme.Op.caption))
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Text(" ").font(.system(size: 11))
                }
            }
            .frame(height: 12)
            Capsule()
                .fill(Color.white.opacity(minute == 0 ? Theme.Op.caption : (minute == 30 ? Theme.Op.faint : 0.25)))
                .frame(width: minute == 0 ? 1.5 : 1, height: minute == 0 ? 14 : (minute == 30 ? 9 : 5))
            Spacer(minLength: 0)
        }
    }

    private func label(hour: Int, weekday: Int) -> String {
        if hour == 0 { return Calendar(identifier: .gregorian).shortWeekdaySymbols[weekday - 1].uppercased() }
        if use24h { return String(format: "%02d", hour) }
        return "\(hour % 12 == 0 ? 12 : hour % 12)\u{2009}\(hour < 12 ? "AM" : "PM")"
    }
}

/// A status: a small icon and its words, close together.
struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// One city, in the manner of Apple's Clock: its name and how it relates to you on the left, its
/// time large and light on the right; then its hours as five day-and-night tiles, and a status line.
struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var nameSize: CGFloat = 20
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 34
    /// The rest of the card's type, scaled with the reader's text size.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
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

    private func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if store.isHere(place) {
                        Image(systemName: "location.fill").font(scaled(12)).accessibilityHidden(true)
                    }
                    Text(place.title).font(scaled(17, .semibold))
                }
                Text(detail(store.moment)).font(scaled(13)).foregroundStyle(Color.white.opacity(Theme.Op.sub))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeMath.time(store.moment, in: place.timeZone, use24h: store.use24h))
                .font(scaled(17)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(minHeight: 64 - 2 * Card.padding)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var fullRow: some View {
        let moment = store.moment
        let cal = place.calendar
        let hour = cal.component(.hour, from: moment), minute = cal.component(.minute, from: moment)
        let large = typeSize.isAccessibilitySize
        // Side by side normally; stacked at accessibility text sizes so nothing is cut off.
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                           : AnyLayout(HStackLayout(alignment: .center, spacing: 0))
        VStack(alignment: .leading, spacing: 0) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // Where you are, on this card rather than a second card for the same place.
                        if hereLabel != nil {
                            Image(systemName: "location.fill")
                                .font(scaled(13))
                                .accessibilityHidden(true)
                        }
                        Text(place.title)
                            .font(.system(size: nameSize, weight: .semibold))
                            .minimumScaleFactor(0.7)
                    }
                    Text(detailWithDay(moment))
                        .font(scaled(13, .medium))
                        .foregroundStyle(Color.white.opacity(Theme.Op.body))
                        .monospacedDigit()
                }
                .lineLimit(large ? 2 : 1)
                if !large { Spacer(minLength: 8) }
                // The time is never cut short: the name gives way first.
                clock(hour: hour, minute: minute)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([place.title, place.person != nil ? place.name : nil, hereLabel, TimeMath.time(moment, in: place.timeZone, use24h: store.use24h),
                                 detail(moment), dayNote(moment), workStatus?.text, sunStatus.map { "sun \($0.text.lowercased())" }]
                                 .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            // The city's hours: two before, the one holding the moment, two after.
            HourTiles(place: place)
                .padding(.top, 10)
            // One status line on every card, always there (so every card is the same height):
            // work on the left, the sun on the right. VoiceOver reads it with the name above.
            statusRow(large: large)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    /// The detail line, with the day in front when it isn't today there ("Tomorrow · +8 hr · UTC+1").
    private func detailWithDay(_ moment: Date) -> String {
        let day = dayLine(moment)
        return day == "Today" ? detail(moment) : "\(day) · \(detail(moment))"
    }

    private func statusRow(large: Bool) -> some View {
        let statusLayout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                 : AnyLayout(HStackLayout(spacing: 8))
        return statusLayout {
            if let work = workStatus {
                Label {
                    Text(work.text)
                } icon: {
                    Image(systemName: work.icon)
                        .foregroundStyle(work.working ? Color.white.opacity(Theme.Op.body) : Theme.moon)
                }
            }
            if !large { Spacer(minLength: 0) }
            if let sun = sunStatus {
                Label {
                    Text(sun.text).monospacedDigit()
                } icon: {
                    sunIcon(sun.icon)
                }
            }
        }
        .font(scaled(13, .medium))
        .foregroundStyle(Color.white.opacity(Theme.Op.body))
        .labelStyle(StatusLabelStyle())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(minHeight: 18 * scale)
    }

    @ViewBuilder private func sunIcon(_ name: String) -> some View {
        switch name {
        case "sunrise.fill":
            Image(systemName: name).symbolRenderingMode(.palette).foregroundStyle(Theme.sun, Color.white)
        case "moon.stars.fill":
            Image(systemName: name).symbolRenderingMode(.palette).foregroundStyle(Theme.moon, Color.white)
        default:
            Image(systemName: name).foregroundStyle(Theme.sun)
        }
    }

    private func clock(hour: Int, minute: Int) -> some View {
        let parts = ClockText.parts(hour: hour, minute: minute, use24h: store.use24h)
        return ClockText.text(parts.digits, suffix: parts.suffix, size: clockSize, weight: .light)
            .foregroundStyle(.white)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    /// "Tue 9 Jun", as everywhere else in the app.
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// The day it is there at the moment shown, against today on your own clock: "Today",
    /// "Tomorrow", "Yesterday", or the date ("Tue 9 Jun").
    private func dayLine(_ moment: Date) -> String {
        let there = place.calendar.dateComponents([.year, .month, .day], from: moment)
        let today = Calendar.current.dateComponents([.year, .month, .day], from: store.now)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let a = utc.date(from: there), let b = utc.date(from: today) else { return TimeMath.fullDay(moment, in: place.timeZone) }
        switch Int((a.timeIntervalSince(b) / 86_400).rounded()) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return TimeMath.fullDay(moment, in: place.timeZone)
        }
    }

    /// ", tomorrow there" for VoiceOver.
    private func dayNote(_ moment: Date) -> String {
        switch TimeMath.dayShift(moment, zone: place.timeZone) {
        case 0: return ""
        case 1: return "tomorrow there"
        case -1: return "yesterday there"
        case let d: return "\(abs(d)) days \(d > 0 ? "ahead" : "behind")"
        }
    }

    /// "My Location · UTC−7" on the card for where you are, else how the city relates to you:
    /// "+8 hr · UTC+1", "+5:30 hr · UTC+5:30", "Your time · UTC−7".
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

/// One search result: the city and its region; its time and offset; added or not.
private struct SearchResultRow: View {
    @EnvironmentObject private var store: CityStore
    let entry: CityEntry
    let added: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Text(WorkWeek.countryName(zoneID: entry.timeZoneID) ?? entry.region.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 14)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            Spacer()
            if let zone = TimeZone(identifier: entry.timeZoneID) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeMath.time(store.now, in: zone, use24h: store.use24h))
                        .font(.system(size: 17)).foregroundStyle(.white).monospacedDigit()
                    Text(TimeMath.offsetLabel(seconds: zone.secondsFromGMT(for: store.now)))
                        .font(.system(size: 13)).foregroundStyle(Color.white.opacity(Theme.Op.caption))
                }
            }
            // As Two Degrees: a quiet check on a city already in the list, nothing on a new one.
            if added {
                Image(systemName: "checkmark").foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
        }
        .contentShape(Rectangle())
    }
}
