import SwiftUI
import WidgetKit

@main
struct MeridianApp: App {
    @StateObject private var store = CityStore(demo: Screenshots.isActive)
    @Environment(\.scenePhase) private var scenePhase
    @State private var termsAccepted = Terms.accepted || (Screenshots.isActive && Screenshots.screen != "terms")

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
                    }
                }
                .task { await Screenshots.run(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}
