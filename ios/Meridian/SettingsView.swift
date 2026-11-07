import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("24-Hour Time", isOn: $store.use24h)
                        .tint(Theme.switchOn)
                    Toggle("Highlight Working Hours", isOn: $store.showWorkHours)
                        .tint(Theme.switchOn)
                    Toggle("Public Holidays Are Days Off", isOn: $store.countHolidays)
                        .tint(Theme.switchOn)
                } header: { header("Time", "clock") } footer: {
                    footer("Each city follows its country's usual working days and hours and its national public holidays. To change a city's, touch and hold its card.")
                }
                .meridianSection()
                Section {
                    Toggle("Show My Location", isOn: $store.useMyLocation)
                        .tint(Theme.switchOn)
                    Toggle("Group by Continent", isOn: $store.continentGroups)
                        .tint(Theme.switchOn)
                    NavigationLink {
                        GroupsList()
                    } label: {
                        HStack {
                            Text("Groups")
                            Spacer()
                            Text("\(store.customGroups.count)")
                                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                } header: { header("Cities", "location") } footer: {
                    footer("Keeps the city you're in on your list, and updates it when you travel. Location Services is used only to name the city, and only on your iPhone. Cities are grouped by continent automatically when your list spans two or more.")
                }
                .meridianSection()
                Section {
                    Text("Touch and hold your Home Screen, tap Edit, then Add Widget and choose Meridian. For the Lock Screen, touch and hold it, tap Customize, then add Meridian to the widget area.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                } header: { header("Widgets", "square.grid.2x2") }
                .meridianSection()
                Section {
                    LabeledContent("Version", value: version)
                    Link("bradcowdrey.com/meridian", destination: Theme.appPage)
                    Link("Source code on GitHub", destination: Theme.source)
                    Link("Terms & Privacy", destination: Theme.legal)
                    NavigationLink {
                        PhotoCreditsView()
                    } label: {
                        HStack {
                            Text("Photo Credits")
                            Spacer()
                            Text("Wikimedia Commons")
                                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                } header: { header("About", "info.circle") }
                .meridianSection()
                Section {
                    Text("Made by Bradley Cowdrey. Free. Forever.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .meridianForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    private func header(_ title: String, _ symbol: String) -> some View {
        CardCaption(title, symbol).textCase(nil)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
    }
}
