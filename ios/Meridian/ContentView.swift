import SwiftUI

/// The whole app on one screen: the moment you're looking at, then one row per city with the
/// day-and-night hours either side of it.
struct ContentView: View {
    @EnvironmentObject private var store: CityStore
    /// Owned here and passed down, so the Edit button, the list and the rows all share it.
    @State private var editMode: EditMode = .inactive
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var copied = false

    /// Hours shown either side of the selected one.
    private let span = 3

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MomentHeader(copied: $copied)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    if store.places.isEmpty {
                        emptyState
                    }
                    ForEach(store.places) { place in
                        CityRow(place: place, span: span)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                            .listRowBackground(Theme.bg)
                            .listRowSeparatorTint(Theme.border)
                    }
                    .onDelete { store.remove(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                } header: {
                    if !store.places.isEmpty { HourHeader(span: span) }
                } footer: {
                    footer
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .safeAreaInset(edge: .top, spacing: 0) { Theme.crimson.frame(height: 3) }
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
                    if !store.places.isEmpty { EditButton() }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!store.canAdd)
                        .accessibilityLabel("Add City")
                    Menu {
                        Button { copyMoment() } label: { Label("Copy This Moment", systemImage: "doc.on.doc") }
                            .disabled(store.places.isEmpty)
                        Toggle(isOn: $store.use24h) { Label("24-Hour Time", systemImage: "clock") }
                        Divider()
                        Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(isPresented: $showingAdd) { AddCityView(query: Screenshots.screen == "add" ? "san" : "") }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .onAppear(perform: openScreenshotScreen)
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
    private func openScreenshotScreen() {
        guard Screenshots.isActive else { return }
        switch Screenshots.screen {
        case "add": showingAdd = true
        case "settings": showingSettings = true
        case "edit": editMode = .active
        case "travel": store.offsetHours = 5
        default: break
        }
    }

        private func copyMoment() {
        UIPasteboard.general.string = store.momentText
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation { copied = false } }
    }
}

/// "Now, your time" and the selected moment, with the time-travel controls.
private struct MomentHeader: View {
    @EnvironmentObject private var store: CityStore
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if store.offsetHours == 0 { Circle().fill(Theme.crimson).frame(width: 7, height: 7) }
                Text(copied ? "Copied" : relative)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(store.offsetHours == 0 ? Theme.muted : Theme.cream)
                    .contentTransition(.opacity)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(TimeMath.fullMoment(store.moment, in: .current, use24h: store.use24h))
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
            }
            HStack(spacing: 10) {
                RoundButton(symbol: "chevron.left", label: "One hour earlier") { store.travel(-1) }
                Button("Now") { store.backToNow() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(store.offsetHours == 0 ? Theme.tile : Theme.cream))
                    .foregroundStyle(store.offsetHours == 0 ? Theme.faint : Theme.bg)
                    .disabled(store.offsetHours == 0)
                RoundButton(symbol: "chevron.right", label: "One hour later") { store.travel(1) }
                Spacer()
            }
            .buttonStyle(.plain)
        }
    }

    private var relative: String {
        let h = store.offsetHours
        if h == 0 { return "Now, your time" }
        let days = abs(h) / 24, hours = abs(h) % 24
        let span = [days > 0 ? "\(days) d" : nil, hours > 0 ? "\(hours) h" : nil].compactMap { $0 }.joined(separator: " ")
        return h > 0 ? "In \(span)" : "\(span) ago"
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 36)
                .background(Capsule().fill(Theme.tile))
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityLabel(label)
    }
}

/// Column labels above the tiles: "−3 … Now … +3" (relative to the selected hour), with a
/// cream mark under hours when every city is within working hours.
private struct HourHeader: View {
    @EnvironmentObject private var store: CityStore
    let span: Int

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CityRow.labelWidth)
            ForEach(-span...span, id: \.self) { k in
                VStack(spacing: 3) {
                    Text(label(k))
                        .font(.system(size: 11, weight: k == 0 ? .semibold : .medium))
                        .foregroundStyle(k == 0 ? Theme.cream : Theme.faint)
                        .monospacedDigit()
                    Capsule().fill(allWorking(k) ? Theme.cream : .clear).frame(width: 14, height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.leading, 0)
        .padding(.vertical, 6)
        .background(Theme.bg)
        .textCase(nil)
        .accessibilityHidden(true)
    }

    private func label(_ k: Int) -> String {
        let fromNow = store.offsetHours + k
        if fromNow == 0 { return "Now" }
        return fromNow > 0 ? "+\(fromNow)" : "−\(-fromNow)"
    }

    private func allWorking(_ k: Int) -> Bool {
        guard store.showWorkHours, store.places.count > 1 else { return false }
        let at = TimeMath.hourAnchor(store.now).addingTimeInterval(Double(store.offsetHours + k) * 3600)
        return store.places.allSatisfy { store.isWorkHour($0.calendar.component(.hour, from: at)) }
    }
}

/// One city: name and time at the selected moment, then its day-and-night hours.
struct CityRow: View {
    static let labelWidth: CGFloat = 118
    @EnvironmentObject private var store: CityStore
    @Environment(\.editMode) private var editMode
    let place: Place
    let span: Int

    var body: some View {
        let moment = store.moment
        let shift = TimeMath.dayShift(moment, zone: place.timeZone)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(TimeMath.time(moment, in: place.timeZone, use24h: store.use24h))
                        .foregroundStyle(Theme.secondary)
                    if shift != 0 {
                        Text(shift > 0 ? "+\(shift) day" : "−\(-shift) day")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.border))
                            .foregroundStyle(Theme.cream)
                    }
                }
                .font(.system(size: 13))
                .monospacedDigit()
                .lineLimit(1)
            }
            .frame(width: Self.labelWidth, alignment: .leading)

            if editMode?.wrappedValue.isEditing != true {
                ForEach(-span...span, id: \.self) { k in
                    tile(k)
                        .onTapGesture { store.travel(k) }
                }
            } else {
                Text(place.offsetLabel(at: moment))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ k: Int) -> some View {
        let at = TimeMath.hourAnchor(store.now).addingTimeInterval(Double(store.offsetHours + k) * 3600)
        let cal = place.calendar
        let hour = cal.component(.hour, from: at), minute = cal.component(.minute, from: at)
        let style = DayColor.style(at: Double(hour) + Double(minute) / 60)
        let newDay = !cal.isDate(at, inSameDayAs: at.addingTimeInterval(-3600))
        let dim = store.showWorkHours && !store.isWorkHour(hour)
        return VStack(spacing: 0) {
            Group {
                if store.use24h {
                    Text(String(format: "%02d", hour))
                } else {
                    Text("\(hour % 12 == 0 ? 12 : hour % 12)") + Text(hour < 12 ? "a" : "p").font(.system(size: 9, weight: .semibold))
                }
            }
            .font(.system(size: 14, weight: k == 0 ? .bold : .medium))
            .monospacedDigit()
            if minute != 0 {
                Text(":\(String(format: "%02d", minute))").font(.system(size: 9, weight: .medium))
            } else if newDay {
                Text(TimeMath.weekday(at, in: place.timeZone)).font(.system(size: 8, weight: .semibold)).textCase(.uppercase)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.fill.opacity(dim ? 0.72 : 1)))
        .overlay {
            if k == 0 { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cream, lineWidth: 2) }
        }
        .overlay(alignment: .leading) {
            if newDay { Capsule().fill(Theme.crimson).frame(width: 2).padding(.vertical, 8).offset(x: -2.5) }
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}
