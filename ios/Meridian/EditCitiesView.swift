import SwiftUI

/// Edit Cities: remove, reorder (drag the handles) and rename (tap a city). Its own sheet with a
/// list that is always in edit mode, as in Apple's Weather and Clock.
struct EditCitiesView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Place?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.places) { place in
                        Button {
                            newName = place.name
                            renaming = place
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                                    Text(place.offsetLabel(at: store.now)).font(.footnote).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(TimeMath.time(store.now, in: place.timeZone, use24h: store.use24h))
                                    .foregroundStyle(Theme.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .listRowBackground(Theme.tile)
                        .accessibilityHint("Renames \(place.name)")
                    }
                    .onDelete { store.remove(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                } footer: {
                    Text(store.places.isEmpty ? "No cities. Tap + on the main screen to add one."
                                              : "Drag the handles to reorder. Tap a city to rename it.")
                        .foregroundStyle(Theme.muted)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Edit Cities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Rename City", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let place = renaming { store.rename(place, to: newName) }
                    renaming = nil
                }
            }
        }
        .tint(Theme.cream)
        .preferredColorScheme(.dark)
    }
}
