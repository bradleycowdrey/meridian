import SwiftUI
import AppKit

@main
struct MeridianApp: App {
    @StateObject private var store = ZoneStore()

    var body: some Scene {
        MenuBarExtra {
            ClockPanel(compact: true)
                .frame(width: Metrics(scale: store.uiSize.scale).popoverWidth)
                .environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        // Optional desktop-widget style window, opened from the menu bar.
        Window(Brand.appName, id: "strip") {
            ClockPanel()
                .environmentObject(store)
                .frame(minWidth: Metrics(scale: store.uiSize.scale).pt(760), minHeight: Metrics(scale: store.uiSize.scale).pt(320))
                .background(WindowConfigurator(floatOnTop: store.floatOnTop))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 440)

        Settings {
            SettingsView().environmentObject(store)
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
