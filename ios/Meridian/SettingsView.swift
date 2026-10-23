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
                Section("Time") {
                    Toggle("24-Hour Time", isOn: $store.use24h)
                    Toggle("Highlight Working Hours", isOn: $store.showWorkHours)
                    if store.showWorkHours {
                        Stepper("Work starts at \(hourLabel(store.workStart))", value: $store.workStart, in: 0...23)
                        Stepper("Work ends at \(hourLabel(store.workEnd))", value: $store.workEnd, in: 1...24)
                    }
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

    private func hourLabel(_ hour: Int) -> String {
        if store.use24h { return String(format: "%02d:00", hour % 24) }
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour % 24 < 12 ? "AM" : "PM")"
    }
}
