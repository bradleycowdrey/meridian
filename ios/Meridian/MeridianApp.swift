import SwiftUI
import WidgetKit

@main
struct MeridianApp: App {
    @StateObject private var store = CityStore(demo: Screenshots.isActive)
    @Environment(\.scenePhase) private var scenePhase
    @State private var termsAccepted = Terms.accepted || (Screenshots.isActive && Screenshots.screen != "terms")
    @State private var askLocation = false

    var body: some Scene {
        WindowGroup {
            Group {
                if Screenshots.isActive && Screenshots.screen == "widgets" { WidgetShowcase() } else { ContentView() }
            }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!termsAccepted)) {
                    TermsView {
                        Terms.accept()
                        termsAccepted = true
                        // Once the terms sheet has gone: the location question.
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            askLocation = !store.locationChosen && !Screenshots.isActive
                        }
                    }
                }
                .onAppear { askLocation = termsAccepted && !store.locationChosen && !Screenshots.isActive }
                .alert(MyLocation.questionTitle, isPresented: $askLocation) {
                    Button("Use My Location") { store.useMyLocation = true }
                        .keyboardShortcut(.defaultAction)
                    Button("Not Now", role: .cancel) { store.useMyLocation = false }
                } message: {
                    Text(MyLocation.questionMessage(device: "iPhone"))
                }
                .task { await Screenshots.run(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refresh()
            // Changed terms on GitHub: ask again (at most once a month).
            Task {
                await TermsVersion.refresh()
                if !Screenshots.isActive && !Terms.accepted { termsAccepted = false }
            }
        }
    }
}
