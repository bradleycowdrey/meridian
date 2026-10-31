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
                    Toggle("Highlight Working Hours", isOn: $store.showWorkHours)
                } header: { Text("Time") } footer: {
                    Text("Each city follows the usual working days and hours where it is: Sunday to Thursday, 8 AM to 5 PM in Riyadh; Monday to Friday, 9 AM to 5 PM in Denver; shorter days in Ramadan and Spain's summer. To change a city's, tap its card, then Working Days & Hours.")
                        .foregroundStyle(Theme.muted)
                }
                Section {
                    Toggle("Show My Location", isOn: $store.useMyLocation)
                } header: { Text("Cities") } footer: {
                    Text("Keeps the city you're in on your list, and updates it when you travel. Location Services is used only to name the city, and only on your iPhone.")
                        .foregroundStyle(Theme.muted)
                }
                Section {
                    Text("Touch and hold your Home Screen, tap Edit, then Add Widget and choose Meridian. For the Lock Screen, touch and hold it, tap Customize, then add Meridian to the widget area.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } header: { Text("Widgets") }
                Section("About") {
                    LabeledContent("Version", value: version)
                    Link("bradcowdrey.com/meridian", destination: Theme.appPage)
                    Link("Source code on GitHub", destination: Theme.source)
                    Link("Terms & Privacy", destination: Theme.legal)
                }
                Section {
                    Text("Made by Bradley Cowdrey. Free. Forever.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.cream)
        .preferredColorScheme(.dark)
    }
}
