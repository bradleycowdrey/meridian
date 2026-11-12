import SwiftUI

/// The whole app on one screen: one card per city (its skyline filling it, its time, name and
/// status, then five hour tiles shaded for day and night), one Now capsule down the list through
/// the hour shown, and the time ruler below. Drag any row of tiles sideways to move through time
/// in quarter-hours; tap a tile to go to that hour.
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
    /// The list's width, for the touch-and-hold preview of a row.
    @State private var listWidth: CGFloat = 390
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
    /// The list's size and safe-area insets, and the bottom bar's own height: what's left between
    /// the top bar and the bottom bar is what up to five city cards share (`listHeight`).
    @State private var listSize: CGFloat = 700
    @State private var listInsets = EdgeInsets()
    @State private var barHeight: CGFloat = 0
    /// Each clock-change notice's height, taken out of what the cards share.
    @State private var noticeHeights: [String: CGFloat] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
            // What shows between the bars (recomputed on rotation, size and bar changes).
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listSize = $0 }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { listInsets = $0 }
            .environment(\.defaultMinListRowHeight, 0)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Meridian's warm near-black, as on the Mac.
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Meridian")
            // The title sits small in the bar, between Share and the + and pencil; never large.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.editMode, $editMode)
            // The group chips pinned at the top.
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            // The time ruler and Now on a frosted bar at the bottom, in thumb reach, as Two Degrees' bar.
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    /// The height between the top bar and the bottom bar. The bottom bar is taken out by its own
    /// measured height whenever the list's bottom inset doesn't already hold it, so the last of
    /// five cards always ends above the bar rather than under it.
    private var listHeight: CGFloat {
        let bar = showBar ? barHeight : 0
        let bottom = listInsets.bottom >= bar ? listInsets.bottom : listInsets.bottom + bar
        return max(0, listSize - listInsets.top - bottom)
    }

    /// The bars, while the cards show (not while adding a city or editing the list).
    private var showBar: Bool { !adding && !editMode.isEditing && !store.places.isEmpty }
    /// The group chips: once there's a group to pick (a custom one, or two continents).
    private var showGroupBar: Bool { showBar && (!store.customGroups.isEmpty || store.continentChipCount >= 2) }

    /// The group chips (the ruler in the bottom bar moves the time; there are no column labels).
    @ViewBuilder private var topBar: some View {
        if showGroupBar {
            VStack(spacing: 0) {
                GroupBar(open: { groupsRoute = $0 }, openSettings: { showingSettings = true })
            }
            .frame(maxWidth: .infinity)
            // Opaque, so a photo scrolled under the chips never shows through behind their labels.
            .background(Theme.bar)
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
                    // Opaque, down to the screen's bottom edge, so nothing in the list (the last
                    // card's name and tiles, the Now capsule) shows through behind the hint, Now
                    // and the ruler's hours.
                    .background(Theme.bar, ignoresSafeAreaEdges: .bottom)
                    // Its height (hint, Now and ruler, not the brief Copied pill), for `listHeight`.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Theme.Op.track)).frame(height: 0.5).accessibilityHidden(true) }
                    .environment(\.colorScheme, .dark)
            }
        }
        .animation(.snappy, value: copied)
    }

    /// Search and Edit List in a list; the cards in a scroll view, so the Now capsule can be drawn
    /// over their content (measured from the cards' own middle tiles) and scroll with them.
    @ViewBuilder private var cityList: some View {
        if adding || editMode.isEditing {
            List {
                if adding {
                    searchField
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty { searchResults } else { searchHint }
                } else {
                    cards
                }
            }
        } else {
            cardScroll
        }
    }

    /// The city cards (not in Edit List): with one to five they share the screen; six or more
    /// scroll. One Now capsule runs down them through every card's middle tile.
    private var cardScroll: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if store.places.isEmpty {
                    emptyState
                }
                ForEach(store.clockChanges) { change in
                    clockNotice(change)
                        .padding(.horizontal, Card.margin)
                        .padding(.vertical, Card.gap / 2)
                }
                if !store.places.isEmpty && store.visiblePlaces.isEmpty, let f = store.groupFilter {
                    emptyGroup(f)
                        .padding(.horizontal, Card.margin)
                }
                let shown = store.visiblePlaces
                let layout = cardLayout(count: shown.count)
                VStack(spacing: 0) {
                    ForEach(shown) { place in
                        scrollRow(place, first: place.id == shown.first?.id, last: place.id == shown.last?.id,
                                  height: layout.height)
                    }
                }
                // Over the cards' content, so it scrolls with them and runs on past the screen's edge.
                .overlayPreferenceValue(NowTileAnchors.self) { anchors in
                    NowCapsule(anchors: anchors)
                }
                // Left out while the cards share the screen exactly (its links are in the More menu and Settings).
                if !layout.fits || shown.isEmpty {
                    footer
                        .padding(.top, 8)
                        .padding(.horizontal, Card.margin)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
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
            .font(.subheadline)
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
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        let results = CityDirectory.search(query)
        if results.isEmpty {
            Text("No places match “\(query)”. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.")
                .font(.subheadline)
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
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
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
        // In Edit List every city shows, so removing and moving follow the full list.
        let shown = editMode.isEditing ? store.places : store.visiblePlaces
        let layout = cardLayout(count: shown.count)
        ForEach(shown) { place in
            row(place, first: place.id == shown.first?.id, last: place.id == shown.last?.id, height: layout.height)
        }
        // Remove and reorder in Edit List only: a sideways swipe on a row drags its hour tiles.
        .onDelete { store.remove(at: $0) }
        .onMove { store.move(from: $0, to: $1) }
        // The last row, not a section footer: a plain list pins footers to the bottom of the screen.
        // Left out while the cards share the screen exactly (its links are in the More menu and Settings).
        if !layout.fits || editMode.isEditing || shown.isEmpty {
            footer
                .listRowInsets(EdgeInsets(top: 8, leading: Card.margin, bottom: 24, trailing: Card.margin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// The city cards' height: with one to five cities they share the height between the top bar
    /// and the bottom bar exactly (after any clock-change notices); with six or more, or
    /// where that would make them too short, they're a fixed height and the list scrolls.
    private func cardLayout(count: Int) -> (height: CGFloat, fits: Bool) {
        let scrolling = (RowCard.scrollHeight * min(max(textScale, 1), 1.3)).rounded()
        guard count > 0, count <= RowCard.maxFitCount, !typeSize.isAccessibilitySize else { return (scrolling, false) }
        let notices = store.clockChanges.reduce(CGFloat(0)) { sum, change in
            sum + (noticeHeights[change.id] ?? 0) + Card.gap
        }
        let n = CGFloat(count)
        let share = ((listHeight - notices - 2 * RowCard.gap - RowCard.gap * (n - 1)) / n).rounded(.down)
        guard share >= RowCard.minFitHeight else { return (scrolling, false) }
        return (share, true)
    }

    /// The group showing has no cities yet: add some, or show every city.
    private func emptyGroup(_ group: String) -> some View {
        VStack(spacing: 14) {
            Text("No cities in \(group) yet.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { groupsRoute = .detail(group) } label: {
                    Text("Add Cities")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(Capsule().fill(Color.white))
                        .foregroundStyle(Color.black)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { withAnimation(.snappy) { store.groupFilter = nil } } label: {
                    Text("Show All")
                        .font(.subheadline.weight(.medium))
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
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.notice)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.headline(use24h: store.use24h))
                    .font(.headline).foregroundStyle(.white)
                if let detail = change.detail {
                    Text(detail).font(.footnote).foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { store.dismiss(change) } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noticeHeights[change.id] = $0 }
        .listRowInsets(EdgeInsets(top: Card.gap / 2, leading: Card.margin, bottom: Card.gap / 2, trailing: Card.margin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    /// A card in the scroll view: its share of the gaps above and below, and the screen's margins.
    private func scrollRow(_ place: Place, first: Bool, last: Bool, height: CGFloat) -> some View {
        rowContent(place, editing: false, first: first, last: last, height: height, capsule: true)
            .padding(.top, first ? RowCard.gap : RowCard.gap / 2)
            .padding(.bottom, last ? RowCard.gap : RowCard.gap / 2)
            .padding(.horizontal, Strip.margin)
    }

    private func row(_ place: Place, first: Bool, last: Bool, height: CGFloat) -> some View {
        // In Edit List the rows go back to compact rows in one panel, drawn row by row behind them
        // (rounded at the top of the first and the bottom of the last).
        let editing = editMode.isEditing
        return rowContent(place, editing: editing, first: first, last: last, height: height, capsule: false)
            .deleteDisabled(!editing)
            .moveDisabled(!editing)
            .listRowInsets(editing
                           ? EdgeInsets(top: 0, leading: Strip.edge, bottom: 0, trailing: Strip.edge)
                           : EdgeInsets(top: first ? RowCard.gap : RowCard.gap / 2, leading: Strip.margin,
                                        bottom: last ? RowCard.gap : RowCard.gap / 2, trailing: Strip.margin))
            .listRowBackground(Group {
                if editing { PanelSegment(first: first, last: last) } else { Color.clear }
            })
            .listRowSeparator(.hidden)
    }

    /// A city: each its own rounded card, its skyline filling it, with its own actions: touch and
    /// hold for the menu (a tap on a tile goes to that hour). No swipe to remove: a sideways swipe
    /// drags the hour tiles, which moves the time for every city.
    private func rowContent(_ place: Place, editing: Bool, first: Bool, last: Bool, height: CGFloat, capsule: Bool) -> some View {
        CityRow(place: place, editing: editing, first: first, last: last, height: height, capsule: capsule)
            .contentShape(Rectangle())
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: editing ? 0 : RowCard.radius, style: .continuous))
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
            } preview: {
                // The city's card on its own.
                CityRow(place: place, first: true, last: true, height: max(height, RowCard.scrollHeight))
                    .frame(width: max(280, listWidth - 2 * Strip.margin))
                    .environmentObject(store)
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
            ShareLink(item: store.momentText, subject: Text("Times for \(TimeMath.fullMoment(store.moment, in: store.home, use24h: store.use24h))"),
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
            Text("No cities yet").font(.title3.weight(.medium)).foregroundStyle(.white)
            Text("Tap + at the top to add one: a city, an airport code like SFO, or a time zone like PST.")
                .font(.subheadline).foregroundStyle(Color.white.opacity(Theme.Op.caption)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// As Two Degrees' footer: small, centred, quiet.
    private var footer: some View {
        VStack(spacing: 6) {
            // Two lines, so the link never splits and no "·" dangles at the end of a line.
            Text("Made by Bradley Cowdrey. Free. Forever.")
            Link("bradcowdrey.com\u{00A0}↗", destination: Theme.website)
            Link("Terms & Privacy", destination: Theme.legal)
        }
        .font(.footnote)
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
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

/// Moves every city through time from the bottom bar, in one row within thumb reach: Now on the
/// left, a ruler from two days back to two ahead (in quarter-hours, under a fixed line) filling the
/// middle, and Go to a Time (the calendar) at the right end. The tiles drag too.
struct TimeShifter: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let goToTime: () -> Void
    /// Go to a Time's glyph grows with the text (as Now does): 17 pt at the default size, up to 26 pt.
    @ScaledMetric(relativeTo: .body) private var calendarMetric: CGFloat = 17
    private var calendarIcon: CGFloat { min(max(calendarMetric, 17), 26) }

    /// White, and the black set on it (as a selected chip).
    private static let light = Color.white
    private static let ink = Color.black

    var body: some View {
        VStack(spacing: 4) {
            if !store.hasScrubbed {
                // One line up to .xxLarge (it may shrink to 90% rather than truncate); from .xxxLarge
                // up it may wrap to two, so it never ends in an ellipsis on a 320 pt-wide iPhone SE.
                // Shown only until the first drag.
                Text("Drag the hours or the ruler.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.white.opacity(Theme.Op.label))
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize >= .xxxLarge ? 2 : 1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    // An instruction, so never larger than the Now button it explains.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            HStack(spacing: 10) {
                nowButton
                TimeRuler()
                    .frame(maxWidth: .infinity)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                Button(action: goToTime) {
                    Image(systemName: "calendar")
                        .font(.system(size: calendarIcon, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(minWidth: 36, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to a Time")
            }
            .padding(.horizontal, 12)
        }
    }

    /// Now as a large pill: light ink on faint glass while the list shows the current time, and
    /// filled white with black ink once the time has moved, so it reads as the way back. Not
    /// `.disabled` at now, which would dim it; the tap simply does nothing then.
    private var nowButton: some View {
        Button { if !store.isNow { store.backToNow() } } label: {
            Text("Now")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 18)
                .frame(minWidth: 68, minHeight: 44)
                .foregroundStyle(store.isNow ? Self.light : Self.ink)
                .background(Capsule().fill(store.isNow ? Color.white.opacity(0.14) : Self.light))
                .overlay(Capsule().strokeBorder(Color.white.opacity(store.isNow ? 0.25 : 0), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .animation(.snappy, value: store.isNow)
        .accessibilityLabel(store.isNow ? "Now" : "Back to now")
        .accessibilityHint(store.isNow ? "" : "Returns every city to the current time.")
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

    /// A quarter-hour's width and the ruler's height, growing with the reader's text size (capped at
    /// accessibility1 below) so the hour labels never run into each other.
    @ScaledMetric(relativeTo: .footnote) private var tick: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 40
    @ScaledMetric(relativeTo: .footnote) private var labelHeight: CGFloat = 16
    private static let span = 4 * 48

    private static func index(_ date: Date, rounded rule: FloatingPointRoundingRule) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 900).rounded(rule))
    }
    private static func date(_ index: Int) -> Date { Date(timeIntervalSinceReferenceDate: Double(index) * 900) }

    /// The quarter-hour that stands for now (the one just begun).
    private var nowIndex: Int { Self.index(store.now, rounded: .down) }
    private var selectedIndex: Int { store.isNow ? nowIndex : Self.index(store.moment, rounded: .toNearestOrAwayFromZero) }

    /// Hours on your clock, as on the first card and Find a Time (San Francisco's in screenshot mode).
    private var calendar: Calendar { store.homeCalendar }

    var body: some View {
        let center = nowIndex
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach((center - Self.span)...(center + Self.span), id: \.self) { i in
                        RulerTick(date: Self.date(i), isNow: i == center, use24h: store.use24h,
                                  labelHeight: labelHeight, calendar: calendar, rulerWidth: geo.size.width)
                            .frame(width: tick, height: height)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy) { position = i } }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - tick) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
        }
        // The fades measure from the ruler's own visible edges (0...width). `.scrollView` is offset
        // by the content margins, which blanked every tick left of the line.
        .coordinateSpace(.named(RulerTick.space))
        .frame(height: height)
        // The fixed line: where you are in time.
        .overlay {
            VStack(spacing: 0) {
                Capsule().fill(Color.white).frame(width: 2, height: 22)
                Spacer(minLength: 0)
            }
            .padding(.top, labelHeight)
            .allowsHitTesting(false)
        }
        // No mask over the whole ruler: the ticks fade towards its ends and each hour label fades as
        // a whole before it reaches an end (RulerTick), so no label is ever cut mid-glyph.
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
    let labelHeight: CGFloat
    /// Your clock (`CityStore.home`).
    let calendar: Calendar
    /// The ruler's visible width, for fading towards its ends.
    let rulerWidth: CGFloat
    /// The ruler's coordinate space, set on its GeometryReader.
    /// `nonisolated` so the `@Sendable` `visualEffect` closures can read it off the main actor.
    nonisolated static let space = "ruler"

    var body: some View {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        VStack(spacing: 3) {
            Group {
                if minute == 0 {
                    Text(label(hour: hour, weekday: parts.weekday ?? 1))
                        .font(.footnote.weight(hour == 0 ? .semibold : .medium))
                        .foregroundStyle(Color.white.opacity(hour == 0 ? 1 : Theme.Op.body))
                        .monospacedDigit()
                        .fixedSize()
                        .visualEffect { [rulerWidth] content, proxy in
                            content.opacity(Self.labelOpacity(proxy.frame(in: .named(RulerTick.space)), width: rulerWidth))
                        }
                } else {
                    Text(" ").font(.footnote)
                }
            }
            .frame(height: labelHeight)
            Capsule()
                .fill(Color.white.opacity(minute == 0 ? Theme.Op.caption : (minute == 30 ? Theme.Op.faint : 0.25)))
                .frame(width: minute == 0 ? 1.5 : 1, height: minute == 0 ? 14 : (minute == 30 ? 9 : 5))
                .visualEffect { [rulerWidth] content, proxy in
                    content.opacity(Self.tickOpacity(proxy.frame(in: .named(RulerTick.space)), width: rulerWidth))
                }
            Spacer(minLength: 0)
        }
    }

    /// An hour label is whole or not there: fully shown until it comes within 16 pt of an end, then
    /// faded as one piece, gone 4 pt before its edge would reach the end (never half a label).
    nonisolated static func labelOpacity(_ frame: CGRect, width: CGFloat) -> Double {
        guard width > 0 else { return 1 }
        let room = min(frame.minX, width - frame.maxX)
        return Double(min(max((room - 4) / 12, 0), 1))
    }

    /// The ticks fade out over the outer 12% at each end, as the ruler's old edge fade.
    nonisolated static func tickOpacity(_ frame: CGRect, width: CGFloat) -> Double {
        guard width > 0 else { return 1 }
        let room = min(frame.midX, width - frame.midX)
        return Double(min(max(room / (width * 0.12), 0), 1))
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

/// One city as a card: its skyline filling it (a photo, shaded for the time of day there, or one
/// drawn for it); along its bottom, over a soft scrim, its time, name, time zone and working status
/// on the left and its hours as five day-and-night tiles on the right (the list's Now capsule runs
/// through the middle one). In Edit List, a compact row (name, offset, time).
struct CityRow: View {
    @EnvironmentObject private var store: CityStore
    /// Downloaded photos, for cities without a bundled one.
    @ObservedObject private var photos = CityPhotos.shared
    /// The row's type, scaled with the reader's text size.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let place: Place
    /// In Edit List: a compact row (name, offset, time) so the delete button and handle fit.
    var editing = false
    /// The top and last rows of the Edit List panel, which bring the panel's inner margin.
    var first = false
    var last = false
    /// The card's height (shared out by the list; see `RowCard`).
    var height: CGFloat = RowCard.scrollHeight
    /// Report the middle tile for the list's Now capsule (on the list, not in the menu's preview).
    var capsule = false
    /// The card's width, for the name column (the tiles take the rest) and the photo's crop.
    @State private var cardWidth: CGFloat = 366
    /// Where the time sits on the card, to judge what's behind it.
    @State private var clockFrame: CGRect = .zero
    private static let cardSpace = "cityCard"

    /// "My Location" for where you are; with the city you're in when this is another city in the
    /// same time zone ("My Location · Boulder" on Denver).
    private var hereLabel: String? {
        guard store.isHere(place) else { return nil }
        if !place.isMyLocation, place.person == nil, let city = store.hereCity, city != place.name { return "My Location · \(city)" }
        return "My Location"
    }

    /// Working, off hours, the weekend, a day off or a holiday (with until or back when in tall
    /// cards); nil when Highlight Working Hours is off.
    private func workStatus(_ moment: Date, detail: Bool) -> WorkStatus? {
        guard store.showWorkHours else { return nil }
        return WorkStatus.of(place, at: moment, start: store.workStart, end: store.workEnd,
                             use24h: store.use24h, withDetail: detail)
    }

    var body: some View {
        if editing { compactRow } else { card }
    }

    private func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    /// The card's text grows with the reader's text size, up to a point (the card's height is set).
    private var capped: CGFloat { min(max(scale, 0.85), 1.25) }

    /// Small type (13 pt and under) grows with the reader's text size but never shrinks below its size.
    private func cardFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * (size <= 13 ? max(capped, 1) : capped), weight: weight)
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
                Text(detail(store.moment)).font(scaled(13)).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeMath.time(store.moment, in: place.timeZone, use24h: store.use24h))
                .font(scaled(17)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(minHeight: 36)
        .padding(.top, first ? Strip.lead + Strip.inset : 8)
        .padding(.bottom, last ? Strip.lead + Strip.inset : 8)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        let moment = store.moment
        let tall = RowCard.isTall(height)
        let status = workStatus(moment, detail: tall)
        // The time grows only a little with the reader's text size.
        let clockSize = (tall ? RowCard.tallClock : RowCard.compactClock) * min(max(scale, 0.9), 1.15)
        let phase = SkylineArt.phase(for: place, at: moment)
        // Its day photo by day, its night photo after dark (when it has one).
        let photo = SkylineArt.photo(for: place, at: moment,
                                     downloaded: store.downloadCityPhotos ? photos.image(for: place) : nil,
                                     downloadedNight: store.downloadCityPhotos ? photos.nightImage(for: place) : nil,
                                     nightSearched: store.downloadCityPhotos && photos.nightSearched(for: place))
        let size = CGSize(width: cardWidth, height: height)
        // Dark digits where the card is bright behind the time, white ones where it's dark.
        let bright = BannerInk.isBright(photo: photo, seed: place.name, phase: phase, size: size,
                                        region: clockRegion(size: size, clockSize: clockSize))
        let content = max(0, cardWidth - 2 * RowCard.sidePadding)
        let tileHeight = min(RowCard.tileHeight, max(28, height - RowCard.topPadding - RowCard.bottomPadding))
        return ZStack(alignment: .bottomLeading) {
            // The card's background (its fill, photo and scrims) fades out over a thin band at its
            // edge (`RowCard.edgeFeather`, following its rounded corners) into the list behind: a
            // blurred rounded rect as its mask. Only this layer fades; the text and tiles above it
            // stay fully opaque, and the mask leaves the layout as it was.
            ZStack {
                Theme.tile
                SkylineBackdrop(seed: place.name, photo: photo, phase: phase)
                CardScrim()
            }
            .mask {
                // Inset by half the band with concentric corners, blurred by a quarter (σ): about 2%
                // at the card's edge and 98% a band in, so it fades out with no visible line.
                RoundedRectangle(cornerRadius: max(0, RowCard.radius - RowCard.edgeFeather / 2), style: .continuous)
                    .padding(RowCard.edgeFeather / 2)
                    .blur(radius: RowCard.edgeFeather / 4)
            }
            .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: Strip.labelGap) {
                VStack(alignment: .leading, spacing: 0) {
                    BannerClock(moment: moment, zone: place.timeZone, use24h: store.use24h, size: clockSize,
                                bright: bright)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: NamedCoordinateSpace.named(Self.cardSpace))
                        } action: { clockFrame = $0 }
                        .padding(.bottom, 2)
                        .layoutPriority(1)
                    info(moment, status: status, tall: tall)
                }
                .frame(width: Strip.labelWidth(content), alignment: .bottomLeading)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([place.title, place.person != nil ? place.name : nil, hereLabel,
                                     TimeMath.time(moment, in: place.timeZone, use24h: store.use24h),
                                     detail(moment), dayNote(moment), status?.spoken]
                                     .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                // The city's hours: two before, the one holding the moment, two after.
                HourTiles(place: place, height: tileHeight, nowAnchor: capsule, fade: false, outlineAbove: first)
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
            .padding(.horizontal, RowCard.sidePadding)
            .padding(.top, RowCard.topPadding)
            .padding(.bottom, RowCard.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .coordinateSpace(.named(Self.cardSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        // The fill now sits inside the masked background above (so it fades with the photo).
        .clipShape(RoundedRectangle(cornerRadius: RowCard.radius, style: .continuous))
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        // A city without a bundled photo: its photo from disk, or asked for once (never blocking).
        .task(id: "\(place.name)|\(place.timeZoneID)|\(store.downloadCityPhotos)") {
            guard store.downloadCityPhotos, !Screenshots.isActive else { return }
            photos.request(place)
        }
    }

    /// The area behind the time in the card's unit square: where it was laid out, or before the
    /// first layout about where it sits (bottom left, above the name).
    private func clockRegion(size: CGSize, clockSize: CGFloat) -> CGRect {
        guard size.width > 1, size.height > 1 else { return CGRect(x: 0, y: 0.4, width: 0.4, height: 0.3) }
        var frame = clockFrame
        if frame.width < 1 || frame.height < 1 {
            let h = clockSize * 1.2
            frame = CGRect(x: RowCard.sidePadding, y: max(0, size.height - RowCard.bottomPadding - h - clockSize * 2.2),
                           width: clockSize * 3, height: h)
        }
        return CGRect(x: frame.minX / size.width, y: frame.minY / size.height,
                      width: frame.width / size.width, height: frame.height / size.height)
    }

    /// The name, the time zone ("UTC−8", "+1 d · UTC+9"), and the working status; what fits the
    /// card's height (the status before the time zone, then the name alone).
    private func info(_ moment: Date, status: WorkStatus?, tall: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            infoStack(moment, status: status, tall: tall, zone: true)
            infoStack(moment, status: status, tall: tall, zone: false)
            nameLine
        }
    }

    private func infoStack(_ moment: Date, status: WorkStatus?, tall: Bool, zone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            nameLine
            if zone {
                Text(zoneText(moment))
                    .font(cardFont(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.middle)
            }
            if let status {
                StatusPill(status: status, showDetail: tall, scale: max(capped, 1), backed: true)
                    .padding(.top, 2)
            }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 4) {
            Text(place.title)
                .font(cardFont(17, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.9)
            if store.isHere(place) {
                Image(systemName: "location.fill")
                    .font(cardFont(11, .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
    }

    /// "UTC−8"; "+1 d · UTC+9" when it's another day there; a person's city first ("Lisbon · UTC").
    private func zoneText(_ moment: Date) -> String {
        var parts: [String] = []
        if place.person != nil { parts.append(place.name) }
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        if shift != 0 { parts.append(shift > 0 ? "+\(shift) d" : "\u{2212}\(-shift) d") }
        parts.append(place.offsetLabel(at: moment))
        return parts.joined(separator: " \u{00B7} ")
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
        let diff = place.timeZone.secondsFromGMT(for: moment) - store.home.secondsFromGMT(for: moment)
        if diff == 0 {
            // Your own city on another day (a date you went to) shows that date instead.
            if place.timeZone.identifier == store.home.identifier, !store.homeCalendar.isDate(moment, inSameDayAs: store.now) {
                return "\(TimeMath.fullDay(moment, in: store.home)) · \(utc)"
            }
            return "\(place.timeZone.identifier == store.home.identifier ? "Your time" : "Same time") · \(utc)"
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
                // As Two Degrees: a quiet check after the name of a city already in the list (the times keep their column).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if added {
                        Image(systemName: "checkmark").font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(Theme.Op.caption)).accessibilityHidden(true)
                    }
                }
                // "California, United States" from the city list (as on Android), else the country.
                Text(entry.countryCode != nil ? entry.region
                     : WorkWeek.countryName(zoneID: entry.timeZoneID) ?? entry.region.replacingOccurrences(of: "_", with: " "))
                    .font(.subheadline).foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            Spacer()
            if let zone = TimeZone(identifier: entry.timeZoneID) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeMath.time(store.now, in: zone, use24h: store.use24h))
                        .font(.body).foregroundStyle(.white).monospacedDigit()
                    Text(TimeMath.offsetLabel(seconds: zone.secondsFromGMT(for: store.now)))
                        .font(.footnote).foregroundStyle(Color.white.opacity(Theme.Op.caption))
                }
            }
        }
        .contentShape(Rectangle())
    }
}
