import SwiftUI

/// Search by city, airport code (SFO), abbreviation (PST) or offset (UTC+5:30); tap to add.
struct AddCityView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var query: String

    init(query: String = "") { _query = State(initialValue: query) }

    private var results: [CityEntry] { CityDirectory.search(query) }

    var body: some View {
        NavigationStack {
            List {
                if !store.canAdd {
                    Text("You can track up to \(CityStore.maxPlaces) cities. Remove one to add another.")
                        .foregroundStyle(Theme.muted)
                } else if query.isEmpty {
                    Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(results) { entry in
                    let added = store.contains(entry)
                    Button {
                        store.add(entry)
                        dismiss()
                    } label: {
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
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                                .foregroundStyle(added ? Theme.faint : Theme.cream)
                        }
                    }
                    .disabled(added || !store.canAdd)
                    .listRowBackground(Theme.tile)
                    .accessibilityHint(added ? "Already added" : "Adds \(entry.name)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City, SFO, PST, UTC+5…")
            .autocorrectionDisabled()
            .navigationTitle("Add City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Theme.cream)
        .preferredColorScheme(.dark)
    }
}
