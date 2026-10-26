import SwiftUI
import AppKit

@main
struct MeridianApp: App {
    @StateObject private var store = ZoneStore()
    @ObservedObject private var updater = Updater.shared

    init() {
        FontRegistry.registerBundledFonts()
        Task { @MainActor in Updater.shared.start() }
        // Keep macOS pointed at this copy's widget (stale copies can hide it from Edit Widgets).
        WidgetRegistration.refresh()
        // Once the app has finished launching, ask for agreement to the terms (first run only).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            Terms.askIfNeeded()
        }
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
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        label.task {
            if SelfTest.isActive { openWindow(id: "strip") }
        }
    }

    @ViewBuilder private var label: some View {
        // A trailing dot in the menu bar whenever an update is waiting.
        let dot = updater.latest == nil ? "" : " •"
        if store.menuBarStyle == .cityTime, let place = store.menuBarPlace {
            // "+1 d" / "−1 d" when that city is already on tomorrow / still on yesterday.
            let shift = TimeMath.dayShift(store.now, zone: place.timeZone)
            let day = shift > 0 ? " +\(shift) d" : (shift < 0 ? " −\(-shift) d" : "")
            Text("\(place.tag) \(TimeMath.time(store.now, in: place.timeZone, use24h: store.use24h))\(day)\(dot)")
                .monospacedDigit()
        } else if dot.isEmpty {
            Image(systemName: "globe")
        } else {
            Text("\(Image(systemName: "globe"))\(dot)")
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
            // Dragging is done by the header's own handle; "movable by background" let AppKit
            // claim clicks meant for the header's buttons at some sizes.
            window.isMovableByWindowBackground = false
            window.titlebarAppearsTransparent = true
            // Reopen where the user last dragged it.
            if window.frameAutosaveName.isEmpty { window.setFrameAutosaveName("MeridianStripWindow") }
        }
    }
}
