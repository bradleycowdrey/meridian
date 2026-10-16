import SwiftUI
import AppKit

@main
struct MeridianApp: App {
    @StateObject private var store = ZoneStore()
    @ObservedObject private var updater = Updater.shared

    init() {
        FontRegistry.registerBundledFonts()
        Task { @MainActor in Updater.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            ClockPanel(compact: true)
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        // Optional desktop-widget style window, opened from the menu bar.
        Window(Brand.appName, id: "strip") {
            ClockPanel()
                .environmentObject(store)
                .environmentObject(updater)
                .background(WindowConfigurator(floatOnTop: store.floatOnTop))
        }
        // The window is exactly the panel's size (whole hour columns, measured height) and
        // follows it when the size setting changes, so nothing can be cut off.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView().environmentObject(store).environmentObject(updater)
        }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: ZoneStore

    var body: some View {
        if store.menuBarStyle == .cityTime, let place = store.menuBarPlace {
            Text("\(place.tag) \(TimeMath.time(store.now, in: place.timeZone, use24h: store.use24h))")
                .monospacedDigit()
        } else {
            Image(systemName: "globe")
        }
    }
}

/// Reaches the hosting NSWindow to float it above other windows and keep it on every Space.
private struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = floatOnTop ? .floating : .normal
            window.collectionBehavior = floatOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
        }
    }
}
