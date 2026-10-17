import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CitiesSettings().tabItem { Label("Cities", systemImage: "globe") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
    }
}

/// Rename in place. Saved when you press Return or leave the field; a blank name is ignored.
private struct CityNameField: View {
    @EnvironmentObject private var store: ZoneStore
    let place: Place
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .font(.body.weight(.medium))
            .focused($focused)
            .onAppear { draft = place.name }
            .onChange(of: place.name) { _, name in if !focused { draft = name } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = store.places.firstIndex(where: { $0.id == place.id }) else {
            draft = place.name
            return
        }
        if store.places[index].name != name { store.places[index].name = name }
        draft = name
    }
}

private struct CitiesSettings: View {
    @EnvironmentObject private var store: ZoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(store.places) { place in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        CityNameField(place: place)
                        Spacer()
                        Text(TimeMath.time(store.now, in: place.timeZone, use24h: store.use24h))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(place.offsetLabel(at: store.now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Button {
                            // After the row's own update, so a focused name field can't
                            // outlive its city.
                            DispatchQueue.main.async { store.remove(place) }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.bordered)
            Text("Drag to reorder. Click a name to rename it. You can also add, remove and reorder cities with Add and Edit in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var store: ZoneStore

    var body: some View {
        Form {
            Picker("Menu bar shows", selection: $store.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
            }
            if store.menuBarStyle == .cityTime {
                Picker("City", selection: Binding(
                    get: { store.menuBarPlace?.id },
                    set: { store.menuBarPlaceID = $0 }
                )) {
                    ForEach(store.places) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Picker("Size", selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.label).tag($0) }
            }
            Toggle("24-hour clock", isOn: $store.use24h)
            Toggle("Highlight working hours", isOn: $store.showWorkHours)
            if store.showWorkHours {
                Stepper("Work starts at \(store.workStart):00", value: $store.workStart, in: 0...23)
                Stepper("Work ends at \(store.workEnd):00", value: $store.workEnd, in: 1...24)
            }
            Toggle("Keep desktop window on top", isOn: $store.floatOnTop)
            Toggle("Open at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            Section("Widget") {
                Text("Add Meridian to your desktop or Notification Center: right-click the desktop, choose Edit Widgets, then search for Meridian. It shows your cities in the same order as here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            UpdateSettings()
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automatic)
            LabeledContent("Version \(updater.currentVersion)") {
                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.isBusy || !updater.canSelfUpdate)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch updater.phase {
        case .checking: return "Checking…"
        case .downloading: return "Downloading the update…"
        case .installing: return "Installing…"
        case .available: return "Meridian \(updater.latest?.version ?? "") is available."
        case .failed(let message): return message
        default:
            guard updater.canSelfUpdate else { return "Updates work in the installed app, not in a development build." }
            guard let date = updater.lastChecked else { return "Not checked yet." }
            return "Up to date. Last checked " + date.formatted(.relative(presentation: .named)) + "."
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            AppMark(size: 72)
            Text(Brand.appName).font(.title.bold())
            Text(Brand.tagline).foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption).foregroundStyle(.tertiary)
            Divider().frame(width: 200).padding(.vertical, 6)
            Text("Made by \(Brand.author)")
            HStack(spacing: 16) {
                Link(Brand.websiteHost, destination: Brand.website)
                Link("Source on GitHub", destination: Brand.repository)
            }
            Text("Free and open source (MIT).").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
