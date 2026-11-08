import SwiftUI

/// Where the Groups sheet opens: the list of groups, one group's cities, or a new group.
enum GroupsRoute: Identifiable, Hashable {
    case manage, create, detail(String)

    var id: String {
        switch self {
        case .manage: return "manage"
        case .create: return "create"
        case .detail(let g): return "detail:" + g
        }
    }
}

/// "1 city", "3 cities", "no cities".
enum GroupText {
    static func count(_ n: Int) -> String {
        n == 0 ? "no cities" : n == 1 ? "1 city" : "\(n) cities"
    }
}

/// The Groups sheet, from the chips, the More menu or an empty group.
struct GroupsSheet: View {
    let route: GroupsRoute
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CityStore
    /// The group made on the New Group form, whose cities are then chosen.
    @State private var created: String?

    var body: some View {
        NavigationStack {
            content
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .manage:
            GroupsList(editOnLeading: true)
                .toolbar { doneButton }
        case .detail(let g):
            GroupDetailView(name: g)
                .toolbar { doneButton }
        case .create:
            if let g = created {
                GroupDetailView(name: g, onRename: { created = $0 })
                    .toolbar { doneButton }
            } else {
                // Cancel and Create on the form itself.
                GroupNameForm(mode: .create) { created = $0 }
            }
        }
    }

    @ToolbarContentBuilder private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { finish() } }
    }

    /// A group just made shows on the list, once it has cities.
    private func finish() {
        if route == .create, let g = created, store.groupCount(g) > 0 {
            withAnimation(.snappy) { store.groupFilter = g }
        }
        dismiss()
    }
}

/// The group chips pinned above the cards: All, your groups in your order, the continents, then
/// New Group (or Edit Groups). Touch and hold a group to edit or delete it.
struct GroupBar: View {
    @EnvironmentObject private var store: CityStore
    let open: (GroupsRoute) -> Void
    let openSettings: () -> Void
    @State private var deleting: String?

    private static let allID = "__all"

    var body: some View {
        let custom = store.customGroups
        let continents = store.chipGroups.filter { store.isContinent($0) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PillChip(title: "All", isOn: store.groupFilter == nil) { select(nil) }
                        .id(Self.allID)
                        .accessibilityLabel("All, \(GroupText.count(store.places.count))")
                    ForEach(custom, id: \.self) { g in
                        customChip(g)
                    }
                    if !custom.isEmpty && !continents.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 0.5, height: 20)
                            .accessibilityHidden(true)
                    }
                    ForEach(continents, id: \.self) { g in
                        continentChip(g)
                    }
                    trailingButton(newGroup: custom.isEmpty)
                }
                .padding(.horizontal, Card.margin)
            }
            .onAppear { proxy.scrollTo(store.groupFilter ?? Self.allID, anchor: .center) }
            .onChange(of: store.groupFilter) { _, new in
                withAnimation(.snappy) { proxy.scrollTo(new ?? Self.allID, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: store.groupFilter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Groups")
        .confirmationDialog("Delete \u{201C}\(deleting ?? "")\u{201D}?", isPresented: isDeleting, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) {
                if let g = deleting { withAnimation(.snappy) { store.deleteGroup(g) } }
                deleting = nil
            }
        } message: {
            Text("The cities stay on your list.")
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func select(_ g: String?) {
        withAnimation(.snappy) { store.groupFilter = g }
    }

    private func customChip(_ g: String) -> some View {
        PillChip(title: g, isOn: store.groupFilter == g) { select(g) }
            .id(g)
            .contextMenu {
                Button { open(.detail(g)) } label: { Label("Edit Group\u{2026}", systemImage: "pencil") }
                Button(role: .destructive) { deleting = g } label: { Label("Delete Group\u{2026}", systemImage: "trash") }
            }
            .accessibilityLabel("\(g), \(GroupText.count(store.groupCount(g)))")
            .accessibilityAction(named: "Edit Group") { open(.detail(g)) }
            .accessibilityAction(named: "Delete Group") { deleting = g }
    }

    private func continentChip(_ g: String) -> some View {
        PillChip(title: g, isOn: store.groupFilter == g) { select(g) }
            .id(g)
            .contextMenu {
                Button { openSettings() } label: { Label("Turn Off Continent Groups", systemImage: "globe") }
            }
            .accessibilityLabel("\(g), \(GroupText.count(store.groupCount(g)))")
    }

    /// Quiet, after the chips: + New Group until there is one, then Edit Groups.
    private func trailingButton(newGroup: Bool) -> some View {
        Button { open(newGroup ? .create : .manage) } label: {
            HStack(spacing: 4) {
                Image(systemName: newGroup ? "plus" : "slider.horizontal.3")
                Text(newGroup ? "New Group" : "Edit Groups")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white.opacity(Theme.Op.sub))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .fixedSize()
    }
}

/// A group's row on the Groups list, pushed by value so renaming or deleting it in Group Detail
/// doesn't tie the open screen to a row that has gone.
struct GroupLink: Hashable {
    let name: String
}

/// Every group: yours (open one to choose its cities; reorder and delete in Edit), and the
/// continents, made automatically.
struct GroupsList: View {
    @EnvironmentObject private var store: CityStore
    /// Edit on the left in the Groups sheet (Done is on the right); on the right when pushed
    /// from Settings, next to Back.
    var editOnLeading = false
    @State private var showingNew = false
    /// A group just made on the New Group form; its cities open once the form has closed.
    @State private var made: String?
    @State private var newGroup: String?
    @State private var pendingDelete: String?

    private var atCap: Bool { store.customGroups.count >= CityStore.maxGroups }

    private var presentContinents: [String] {
        let present = Set(store.places.compactMap { Continent.name(for: $0) })
        return Continent.ordered.filter { present.contains($0) && !store.customGroups.contains($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(store.customGroups, id: \.self) { g in
                    NavigationLink(value: GroupLink(name: g)) {
                        HStack {
                            Text(g).foregroundStyle(.white)
                            Spacer()
                            Text(GroupText.count(store.groupCount(g)))
                                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                }
                .onMove { store.moveGroups(from: $0, to: $1) }
                // Deleted only once confirmed.
                .onDelete { offsets in pendingDelete = offsets.map { store.customGroups[$0] }.first }
                Button { showingNew = true } label: {
                    Label("New Group\u{2026}", systemImage: "plus.circle")
                }
                .disabled(atCap)
            } header: {
                CardCaption("Your Groups", "square.stack").textCase(nil)
            } footer: {
                footer(atCap ? "You can have up to \(CityStore.maxGroups) groups."
                             : "Show one group at a time on your list, and pick a group in Find a Time.")
            }
            .meridianSection()
            Section {
                Toggle("Group by Continent", isOn: $store.continentGroups)
                    .tint(Theme.switchOn)
                if store.continentGroups {
                    ForEach(presentContinents, id: \.self) { c in
                        HStack {
                            Text(c)
                            Spacer()
                            Text(GroupText.count(store.groupCount(c)))
                        }
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                CardCaption("Continents", "globe").textCase(nil)
            } footer: {
                footer("Cities are grouped by continent automatically. Continent chips show when your list spans two or more.")
            }
            .meridianSection()
        }
        .meridianForm()
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: editOnLeading ? .topBarLeading : .topBarTrailing) {
                EditButton().disabled(store.customGroups.isEmpty)
            }
        }
        .sheet(isPresented: $showingNew, onDismiss: {
            if let g = made { made = nil; newGroup = g }
        }) {
            NavigationStack {
                GroupNameForm(mode: .create) { made = $0; showingNew = false }
            }
            .tint(.white)
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
        }
        .navigationDestination(item: $newGroup) { g in GroupDetailView(name: g) }
        .navigationDestination(for: GroupLink.self) { link in GroupDetailView(name: link.name) }
        .confirmationDialog("Delete \u{201C}\(pendingDelete ?? "")\u{201D}?", isPresented: isDeleting, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) {
                if let g = pendingDelete { withAnimation(.snappy) { store.deleteGroup(g) } }
                pendingDelete = nil
            }
        } message: {
            Text("The cities stay on your list.")
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
    }
}

/// Naming a new group, with what's wrong with the name shown as you type.
struct GroupNameForm: View {
    enum Mode { case create }

    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onCreate: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(mode: Mode, onCreate: @escaping (String) -> Void) {
        self.mode = mode
        self.onCreate = onCreate
    }

    /// Nothing while the field is empty; then why the name can't be used, if it can't.
    private var problem: String? {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : store.groupNameProblem(draft)
    }

    var body: some View {
        Form {
            Section {
                TextField("Design Team", text: $draft)
                    .textInputAutocapitalization(.words)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(create)
            } footer: {
                Text(problem ?? "Name a group of cities, like your team or family.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            .meridianSection()
        }
        .meridianForm()
        .navigationTitle("New Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: create)
                    .disabled(store.groupNameProblem(draft) != nil)
            }
        }
        .onAppear { focused = true }
    }

    private func create() {
        if let g = store.createGroup(draft) { onCreate(g) }
    }
}

/// One group: its name (renamed in place) and a checklist of every city, which saves as you go.
struct GroupDetailView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var draft = ""
    @State private var query = ""
    @State private var confirmDelete = false
    private let onRename: (String) -> Void

    init(name: String, onRename: @escaping (String) -> Void = { _ in }) {
        _name = State(initialValue: name)
        self.onRename = onRename
    }

    private var members: Set<UUID> {
        Set(store.places.filter { ($0.groups ?? []).contains(name) }.map(\.id))
    }

    private var allIn: Bool { !store.places.isEmpty && members.count == store.places.count }

    private var filtered: [Place] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.places }
        return store.places.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(commitName)
            } header: {
                CardCaption("Name", "character.cursor.ibeam").textCase(nil)
            } footer: {
                if draft != name, let problem = store.groupNameProblem(draft, renaming: name) {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                }
            }
            .meridianSection()
            Section {
                if store.places.isEmpty {
                    Text("Add cities to your list first.")
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                }
                ForEach(filtered) { place in
                    row(place, member: members.contains(place.id))
                }
            } header: {
                HStack {
                    CardCaption("Cities", "building.2").textCase(nil)
                    Spacer()
                    if !store.places.isEmpty {
                        Button(allIn ? "Select None" : "Select All") {
                            store.setMembers(allIn ? [] : Set(store.places.map(\.id)), of: name)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Changes save as you go.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            .meridianSection()
            Section {
                Button("Delete Group", role: .destructive) { confirmDelete = true }
            }
            .meridianSection()
        }
        .meridianForm()
        .modifier(SearchWhenLong(on: store.places.count > 10, text: $query))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = name }
        .onDisappear { commitName() }
        .onChange(of: store.customGroups) { _, groups in
            // Deleted (here or elsewhere): there's nothing left to show.
            if !groups.contains(name) { dismiss() }
        }
        .confirmationDialog("Delete \u{201C}\(name)\u{201D}?", isPresented: $confirmDelete, titleVisibility: .visible) {
            // Closes this screen once the group has gone (see onChange above).
            Button("Delete Group", role: .destructive) { withAnimation(.snappy) { store.deleteGroup(name) } }
        } message: {
            Text("The cities stay on your list.")
        }
    }

    private func row(_ place: Place, member: Bool) -> some View {
        Button {
            var ids = members
            if member { ids.remove(place.id) } else { ids.insert(place.id) }
            store.setMembers(ids, of: name)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.title).foregroundStyle(.white)
                    if place.person != nil {
                        Text(place.name)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                    }
                }
                Spacer()
                Text(TimeMath.time(store.now, in: place.timeZone, use24h: store.use24h))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .opacity(member ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(member ? .isSelected : [])
    }

    /// Renames the group when the new name can be used; otherwise puts the name back.
    private func commitName() {
        let new = CityStore.normalizedGroupName(draft)
        guard new != name, store.customGroups.contains(name), store.renameGroup(name, to: draft) else {
            draft = name
            return
        }
        name = new
        draft = new
        onRename(new)
    }
}

/// Search the cities only when there are enough to need it.
private struct SearchWhenLong: ViewModifier {
    let on: Bool
    @Binding var text: String

    @ViewBuilder func body(content: Content) -> some View {
        if on {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        } else {
            content
        }
    }
}

/// A card's groups, from its menu: tick a group to put the card in it (saved at once), or make one.
struct GroupPicker: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    let placeID: UUID
    @State private var naming = false

    private var place: Place? { store.places.first { $0.id == placeID } }

    var body: some View {
        NavigationStack {
            Form {
                if let place {
                    groupsSection(place)
                }
            }
            .meridianForm()
            .navigationTitle(place?.title ?? "Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: place == nil) { _, gone in if gone { dismiss() } }
            .sheet(isPresented: $naming) {
                NavigationStack {
                    GroupNameForm(mode: .create) { g in
                        if let place { store.setGroups((place.groups ?? []) + [g], for: place) }
                        naming = false
                    }
                }
                .tint(.white)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium])
            }
        }
        .tint(.white)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func groupsSection(_ place: Place) -> some View {
        Section {
            ForEach(store.customGroups, id: \.self) { g in
                let on = (place.groups ?? []).contains(g)
                Button {
                    let current = place.groups ?? []
                    store.setGroups(on ? current.filter { $0 != g } : current + [g], for: place)
                } label: {
                    HStack {
                        Text(g).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .opacity(on ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button { naming = true } label: {
                Label("New Group\u{2026}", systemImage: "plus.circle")
            }
            .disabled(store.customGroups.count >= CityStore.maxGroups)
            if store.continentGroups, let continent = Continent.name(for: place) {
                Text("\(continent) · automatic")
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
        } footer: {
            Text("Add this card to as many groups as you like.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
        }
        .meridianSection()
    }
}
