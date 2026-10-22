import SwiftUI
import AppKit

/// The whole app in one panel: header, the moment, ribbons. Used by both the
/// menu bar popover and the desktop window.
struct ClockPanel: View {
    @EnvironmentObject private var store: ZoneStore
    var compact = false

    var body: some View {
        let ui = Metrics(scale: store.uiSize.scale, family: store.appFont)
        let screen = NSScreen.main?.visibleFrame.width ?? 1440
        ClockPanelContent(compact: compact)
            .frame(width: ui.panelWidth(compact: compact, screenWidth: screen - 48))
            .environment(\.metrics, ui)
    }
}

private struct ClockPanelContent: View {
    @EnvironmentObject private var store: ZoneStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui
    let compact: Bool
    @State private var adding = false
    @State private var editing = false
    @State private var contentHeight: CGFloat = 0
    /// Height of the window's hidden title bar. The panel draws under it (so the crimson rule
    /// is at the very top), and SwiftUI still adds it to the window height, so it's subtracted
    /// at the bottom to keep the window exactly the size of the panel.
    @State private var titleBarInset: CGFloat = 0
    @State private var host = HostWindow()
    @Environment(\.openWindow) private var openWindow

    init(compact: Bool) {
        self.compact = compact
    }

    /// Tallest the scrolling body may be so the whole panel stays on screen at any size.
    private var maxBodyHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        let chrome = 3 + ui.l + ui.xs + ui.pt(32) + ui.m   // crimson rule + header
        return max(ui.pt(240), screen - chrome - ui.pt(compact ? 32 : 64))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Crimson rule and header together act as the window's title bar: drag anywhere
            // that isn't a button to move the window.
            VStack(alignment: .leading, spacing: 0) {
                // bradcowdrey.com's signature crimson rule.
                Palette.crimson.frame(height: 3)

                header
                    .padding(.horizontal, ui.xl)
                    .padding(.top, ui.l + ui.xs)
                    .padding(.bottom, ui.m)
            }
            // Window: drag to move. Menu bar panel (which macOS pins under its icon): drag to
            // tear it off into a movable window at the same spot.
            .background(WindowDragHandle(onTearOff: compact ? { tearOff() } : nil))
            .help(compact ? "Drag to detach into a window" : "")

            // Everything below the header scrolls if it would outgrow the screen
            // (e.g. Extra Large with the city search open).
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ui.m) {
                    // Only takes space when there's something to say.
                    if updater.latest != nil || updater.notice != nil || updater.userChecking {
                        UpdateBanner()
                    }
                    TravelBar()

                    if adding || store.places.isEmpty {
                        Tile { AddCityField() }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !store.places.isEmpty {
                        Tile {
                            StripView(
                                cellWidth: ui.cellWidth(compact: compact),
                                rowHeight: ui.rowHeight(compact: compact),
                                labelWidth: ui.labelWidth(compact: compact),
                                editing: editing
                            )
                        }
                    }

                    HStack(spacing: ui.m) {
                        Link(destination: Brand.website) {
                            Text("Made by \(Brand.author). Free. Forever. · \(Brand.websiteHost) ↗")
                        }
                        .font(ui.font(12))
                        .foregroundStyle(Palette.textMuted)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, ui.xl)
                .padding(.top, ui.xs)
                .padding(.bottom, ui.l + ui.xs)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight > 0 ? min(contentHeight, maxBodyHeight) : nil)
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        // Watch the panel's own size and fit the hosting window to it.
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
            fitWindow(to: size)
        }
        .padding(.bottom, -titleBarInset)
        .background(Palette.bg)
        // Use the full window: the crimson rule sits at the very top, under the hidden title bar.
        .ignoresSafeArea()
        .background(Palette.bg.ignoresSafeArea())
        .background(HostWindowReader(box: { host.isDesktop = !compact; return host }()) { window in
            guard !compact else { return }
            window.backgroundColor = NSColor(Palette.bg)
            let inset = max(0, window.frame.height - window.contentLayoutRect.height)
            if abs(inset - titleBarInset) > 0.5 { titleBarInset = inset }
            SelfTest.log("window attached, title bar inset \(inset)")
        })
        // Measure the whole panel and size the hosting window to it. SwiftUI's menu bar panel
        // (and sometimes a title-less window) doesn't grow on its own when content gets bigger,
        // which clipped the larger sizes.

        .environment(\.colorScheme, .dark)
        .onAppear {
            store.tick()
            Task { await Updater.shared.checkIfDue() }
        }
        .task {
            if !compact && SelfTest.isActive {
                await SelfTest.run(store: store, adding: $adding, editing: $editing, host: host)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onChange(of: store.places.isEmpty) { _, empty in if empty { editing = false } }
        .onChange(of: store.canAdd) { _, canAdd in if !canAdd { withAnimation(.snappy) { adding = false } } }
        .onKeyPress(.leftArrow) { store.travel(-1); return .handled }
        .onKeyPress(.rightArrow) { store.travel(1); return .handled }
        .onKeyPress(.escape) {
            guard adding || editing else { return .ignored }
            withAnimation(.snappy) { adding = false; editing = false }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            store.stepSize(press.characters == "-" ? -1 : 1)
            return .handled
        }
    }

    /// Resizes the hosting window to exactly the panel's size, keeping its top edge where it is
    /// and the whole window on screen.
    private func fitWindow(to size: CGSize, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.1)) {
            guard size.width > 1, size.height > 1 else { return }
            guard let window = host.window, let content = window.contentView else {
                // The window reference arrives a moment after first layout; try again briefly.
                if attempt < 10 { fitWindow(to: size, attempt: attempt + 1) }
                return
            }
            let chrome = CGSize(width: window.frame.width - content.bounds.width,
                                height: window.frame.height - content.bounds.height)
            var frame = window.frame
            let top = frame.maxY
            frame.size = CGSize(width: size.width + chrome.width, height: size.height + chrome.height)
            frame.origin.y = top - frame.height
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                if frame.minY < visible.minY { frame.origin.y = visible.minY }
                if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            }
            SelfTest.log("fitWindow content \(size) window \(window.frame) -> \(frame) titleBarInset \(titleBarInset)")
            if abs(frame.width - window.frame.width) > 0.5 || abs(frame.height - window.frame.height) > 0.5
                || abs(frame.minX - window.frame.minX) > 0.5 || abs(frame.minY - window.frame.minY) > 0.5 {
                window.setFrame(frame, display: true)
            }
            host.keepOnScreen()
        }
    }

    /// Detaches the menu bar panel into the desktop window, placed where the panel was.
    private func tearOff() {
        if let frame = host.window?.frame {
            WindowPlacement.request(.topLeft(NSPoint(x: frame.minX, y: frame.maxY)))
        }
        openWindow(id: "strip")          // placed before it's shown, then fades in
        NSApp.activate(ignoringOtherApps: true)
        host.window?.close()             // the panel goes away in the same beat
    }

    private var header: some View {
        HStack(spacing: ui.m) {
            AppMark(size: ui.pt(28))
            Text(Brand.appName)
                .font(ui.title)
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
            ShareLink(
                item: Brand.repository,
                subject: Text("Meridian for Mac"),
                message: Text(Brand.shareMessage)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .lineLimit(1)
            }
            .buttonStyle(PillButtonStyle(small: true))
            .fixedSize()
            .help("Share Meridian")
            .testID("share")
            Spacer(minLength: ui.s)
            ListControls(adding: $adding, editing: $editing)
            if compact {
                HeaderCircleButton(symbol: "macwindow", help: "Open as Window") { tearOff() }
            }
            MoreMenu(compact: compact, closeHost: { host.window?.close() })
        }
    }
}

/// An area that moves its window when dragged (the window has no visible title bar), or, in the
/// menu bar panel, tears the panel off into a window once the pointer moves a few points.
private struct WindowDragHandle: NSViewRepresentable {
    var onTearOff: (() -> Void)?

    final class DragView: NSView {
        var onTearOff: (() -> Void)?
        private var start: NSPoint?

        override var mouseDownCanMoveWindow: Bool { onTearOff == nil }

        override func mouseDown(with event: NSEvent) {
            if onTearOff == nil {
                window?.performDrag(with: event)
            } else {
                start = event.locationInWindow
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let onTearOff else { return }
            let p = event.locationInWindow
            if hypot(p.x - start.x, p.y - start.y) > 4 {
                self.start = nil
                onTearOff()
            }
        }

        override func mouseUp(with event: NSEvent) { start = nil }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onTearOff = onTearOff
        return view
    }

    func updateNSView(_ view: DragView, context: Context) { view.onTearOff = onTearOff }
}

/// Outlined circle button matching the ⋯ menu, for header actions.
private struct HeaderCircleButton: View {
    @Environment(\.metrics) private var ui
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ui.font(13, .semibold))
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: ui.pt(32), height: ui.pt(32))
                .background(Circle().fill(hovering ? Palette.border : Palette.raisedTile))
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Where to put the desktop window. Requests are applied by the window itself (see HostWindow),
/// the moment it exists, so a newly opened window is positioned before it's ever seen.
enum WindowPlacement: String, CaseIterable, Identifiable {
    case left, center, right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    enum Request {
        case edge(WindowPlacement)
        case topLeft(NSPoint)
    }

    /// The latest unapplied request (one at a time).
    static var pending: Request?
    static let didRequest = Notification.Name("MeridianPlaceWindow")

    static func request(_ request: Request) {
        pending = request
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    /// Top-left point for a window of `size` on `visible`, 16pt from the screen edges.
    static func topLeft(for request: Request, size: CGSize, visible: CGRect) -> NSPoint {
        let margin: CGFloat = 16
        switch request {
        case .topLeft(let point):
            return point
        case .edge(.left):
            return NSPoint(x: visible.minX + margin, y: visible.maxY - margin)
        case .edge(.center):
            return NSPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.maxY - margin)
        case .edge(.right):
            return NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - margin)
        }
    }
}

/// Holds the NSWindow hosting the panel (the menu bar popover or the desktop window), and keeps
/// that window fully on screen: after any resize, from SwiftUI or from us, it is pulled back
/// inside the screen's visible area (top edge first, so the header is never lost).
final class HostWindow {
    /// True for the desktop window, which applies WindowPlacement requests.
    var isDesktop = false
    weak var window: NSWindow? {
        didSet { if window !== oldValue { observe() } }
    }
    private var observers: [NSObjectProtocol] = []

    private func observe() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.centerUnderMenuBarItem()
                self?.keepOnScreen()
            })
        }
        if !isDesktop {
            // The menu bar panel is placed by the system as it opens; centre it right after.
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.centerUnderMenuBarItem()
            })
            centerUnderMenuBarItem()
        }
        if isDesktop {
            observers.append(NotificationCenter.default.addObserver(forName: WindowPlacement.didRequest, object: nil, queue: .main) { [weak self] _ in
                self?.applyPlacement(animated: true)
            })
            applyPlacement(animated: false)
        }
        keepOnScreen()
    }

    /// Applies a pending placement. A brand-new window is placed while still invisible and then
    /// faded in; an open window glides to its new spot.
    func applyPlacement(animated: Bool) {
        guard isDesktop, let window, let request = WindowPlacement.pending,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        WindowPlacement.pending = nil
        let topLeft = WindowPlacement.topLeft(for: request, size: window.frame.size, visible: visible)
        var frame = window.frame
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        SelfTest.log("placement \(request) -> \(frame) visible \(visible)")
        if animated && window.isVisible {
            window.setFrame(frame, display: true, animate: true)
            keepOnScreen()
        } else {
            window.alphaValue = 0
            window.setFrame(frame, display: false)
            keepOnScreen()
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    window.animator().alphaValue = 1
                }
            }
        }
    }

    /// Menu bar panel: horizontally centred under Meridian's menu bar item, moved sideways only
    /// as far as needed to stay on screen. The vertical position stays where the system put it.
    func centerUnderMenuBarItem() {
        guard !isDesktop, let window, let item = HostWindow.menuBarItemFrame(),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let width = window.frame.width
        let x = min(max((item.midX - width / 2).rounded(), visible.minX), max(visible.minX, visible.maxX - width))
        if abs(window.frame.minX - x) > 0.5 {
            SelfTest.log("centre panel under menu bar item \(item): x \(window.frame.minX) -> \(x)")
            window.setFrameOrigin(NSPoint(x: x, y: window.frame.minY))
        }
    }

    /// Screen frame of this app's menu bar item (the status bar window holding its button).
    static func menuBarItemFrame() -> NSRect? {
        NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBarWindow") && $0.frame.width > 0 }?.frame
    }

    func keepOnScreen() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var origin = window.frame.origin
        let size = window.frame.size
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        if origin.y + size.height > visible.maxY { origin.y = visible.maxY - size.height }
        if origin.y < visible.minY { origin.y = min(visible.minY, visible.maxY - size.height) }
        if origin != window.frame.origin {
            SelfTest.log("keepOnScreen moved \(window.frame) -> origin \(origin) visible \(visible)")
            window.setFrameOrigin(origin)
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

private struct HostWindowReader: NSViewRepresentable {
    let box: HostWindow
    var onWindow: ((NSWindow) -> Void)? = nil

    /// Reports its window as soon as it's attached (before the window is first drawn).
    final class ReaderView: NSView {
        var box: HostWindow?
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if let box, box.window !== window { box.window = window }
            let callback = onWindow
            DispatchQueue.main.async { callback?(window) }
        }
    }

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.box = box
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.box = box
        view.onWindow = onWindow
        if box.window !== view.window, view.window != nil { box.window = view.window }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One hairline capsule holding Add City | Edit. Quiet at rest; the active segment fills cream.
private struct ListControls: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    @Binding var adding: Bool
    @Binding var editing: Bool

    var body: some View {
        HStack(spacing: 0) {
            Segment(
                symbol: adding ? "checkmark" : "plus",
                title: adding ? "Done" : "Add City",
                width: ui.pt(104),
                active: adding,
                enabled: store.canAdd || adding,
                help: store.canAdd ? "Add a city" : "You can track up to \(ZoneStore.maxPlaces) cities"
            ) {
                withAnimation(.snappy) { adding.toggle(); if adding { editing = false } }
            }
            .testID("control-add")
            Palette.borderStrong.frame(width: 0.5, height: ui.pt(14))
                .opacity(adding || editing ? 0 : 1)
            Segment(
                symbol: editing ? "checkmark" : "pencil",
                title: editing ? "Done" : "Edit",
                width: ui.pt(80),
                active: editing,
                enabled: !store.places.isEmpty,
                help: "Remove or reorder cities"
            ) {
                withAnimation(.snappy) { editing.toggle(); if editing { adding = false } }
            }
            .testID("control-edit")
        }
        .padding(ui.pt(3))
        .background(Capsule().fill(Palette.raisedTile))
        .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
    }

    private struct Segment: View {
        @Environment(\.metrics) private var ui
        let symbol: String
        let title: String
        /// Fixed so the control doesn't change width when a label becomes "Done".
        let width: CGFloat
        let active: Bool
        let enabled: Bool
        let help: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: ui.pt(6)) {
                    Image(systemName: symbol)
                        .font(ui.font(11, .semibold))
                    Text(title)
                        .font(ui.font(13, .medium))
                }
                .frame(width: width, height: max(24, ui.pt(26)))
                .foregroundStyle(active ? Palette.bg : (enabled ? (hovering ? Palette.textPrimary : Palette.textSecondary) : Palette.textFaint))
                .background(
                    Capsule().fill(active ? Palette.cream : (hovering && enabled ? Palette.border : .clear))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.snappy, value: active)
            .help(help)
        }
    }
}

/// Everything secondary lives behind one ⋯ button.
private struct MoreMenu: View {
    @EnvironmentObject private var store: ZoneStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let compact: Bool
    /// Closes the menu bar panel this menu lives in.
    let closeHost: () -> Void

    var body: some View {
        Menu {
            if let release = updater.latest {
                Button("Install Meridian \(release.version)…") { Task { await updater.install() } }
                    .disabled(updater.isBusy)
                Divider()
            }
            Button("Copy This Moment") { store.copyMoment() }
                .disabled(store.places.isEmpty)
            Divider()
            Picker("Size", selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.label).tag($0) }
            }
            Button("Larger") { store.stepSize(1) }
                .keyboardShortcut("+")
                .disabled(store.uiSize.larger == nil)
                .disabled(store.uiSize.larger == nil)
            Button("Smaller") { store.stepSize(-1) }
                .keyboardShortcut("-")
                .disabled(store.uiSize.smaller == nil)
                .disabled(store.uiSize.smaller == nil)
            Divider()
            if compact {
                Button("Open as Window") {
                    closeHost()
                    openWindow(id: "strip")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Menu("Window Position") {
                ForEach(WindowPlacement.allCases) { placement in
                    Button(placement.label) {
                        WindowPlacement.request(.edge(placement))
                        openWindow(id: "strip")   // opens it, or brings the open one forward
                        NSApp.activate(ignoringOtherApps: true)
                        if compact { closeHost() }
                    }
                }
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Terms & Privacy") { NSWorkspace.shared.open(Brand.legal) }
            Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                .disabled(updater.isBusy || !updater.canSelfUpdate)
            Divider()
            Button("Quit Meridian") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(ui.font(13, .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: ui.pt(32), height: ui.pt(32))
                .background(Circle().fill(Palette.raisedTile))
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

/// Shown only when a newer version is out: one line and one button.
private struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater
    @Environment(\.metrics) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: ui.s) {
            // An available update is always shown, above any other status, until it's installed.
            if let release = updater.latest {
                row {
                    Circle().fill(Palette.crimson).frame(width: ui.pt(7), height: ui.pt(7))
                    Text("Meridian \(release.version) is available")
                        .font(ui.font(14, .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    // Room for the progress message while it downloads and installs.
                    if !updater.isBusy {
                        Text("You have \(updater.currentVersion)")
                            .font(ui.meta)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: ui.s)
                    switch updater.phase {
                    case .downloading:
                        ProgressView().controlSize(.small)
                        message("Downloading…")
                    case .installing:
                        ProgressView().controlSize(.small)
                        message("Installing, Meridian will restart…")
                    default:
                        Button("Update") { Task { await updater.install() } }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    }
                }
            }

            if updater.userChecking {
                row {
                    ProgressView().controlSize(.small)
                    message("Checking for updates…")
                }
            } else if let notice = updater.notice {
                row {
                    Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(ui.font(14, .semibold))
                        .foregroundStyle(notice.isError ? Palette.crimson : Palette.cream)
                    message(notice.text)
                    Spacer(minLength: ui.s)
                    if notice.isError {
                        Button("Retry") {
                            Task {
                                if updater.latest != nil { await updater.install() } else { await updater.check(userInitiated: true) }
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        Button("Download") { updater.openReleasePage() }
                            .buttonStyle(PillButtonStyle())
                    }
                    IconButton(symbol: "xmark", help: "Dismiss") { updater.dismissNotice() }
                }
            }
        }
        .animation(.snappy, value: updater.notice)
        .animation(.snappy, value: updater.userChecking)
        .animation(.snappy, value: updater.latest)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(ui.meta)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: ui.m) { content() }
            .frame(maxWidth: .infinity, minHeight: ui.pt(34), alignment: .leading)
            .padding(.leading, ui.l)
            .padding(.trailing, ui.pt(6))
            .padding(.vertical, ui.pt(6))
            .background(RoundedRectangle(cornerRadius: ui.pt(22), style: .continuous).fill(Palette.raisedTile))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The moment you're looking at, apple.com-style, and the travel controls.
struct TravelBar: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui

    var body: some View {
        let moment = store.selectedMoment()
        // One quiet line: the strip below is the focus, not the clock.
        HStack(spacing: ui.s) {
            if store.offsetHours == 0 {
                Circle().fill(Palette.crimson).frame(width: ui.pt(6), height: ui.pt(6))
            }
            Text(relativeLabel)
                .font(ui.font(13, .medium))
                .foregroundStyle(store.offsetHours == 0 ? Palette.textMuted : Palette.cream)
            Text(TimeMath.fullMoment(moment, in: .current, use24h: store.use24h))
                .font(ui.font(15, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
            if dayOffset != 0 {
                Text(dayOffset > 0 ? "+\(dayOffset) day\(dayOffset == 1 ? "" : "s")" : "−\(-dayOffset) day\(dayOffset == -1 ? "" : "s")")
                    .font(ui.font(11, .medium))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, ui.pt(7))
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.borderStrong))
                    .transition(.opacity)
            }
            Spacer(minLength: ui.m)
            IconButton(symbol: "chevron.left", help: "One hour earlier", small: true) { store.travel(-1) }
                .testID("travel-earlier")
            Button("Now") { store.backToNow() }
                .buttonStyle(PillButtonStyle(prominent: store.offsetHours != 0, small: true))
                .disabled(store.offsetHours == 0)
                .testID("travel-now")
            IconButton(symbol: "chevron.right", help: "One hour later", small: true) { store.travel(1) }
                .testID("travel-later")
        }
        .animation(.snappy, value: store.offsetHours)
    }

    /// Calendar days between today and the moment being viewed (your own time zone).
    private var dayOffset: Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: store.now)
        let to = calendar.startOfDay(for: store.selectedMoment())
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private var relativeLabel: String {
        let h = store.offsetHours
        if h == 0 { return "Now" }
        let days = abs(h) / 24
        let hours = abs(h) % 24
        var parts: [String] = []
        if days > 0 { parts.append("\(days) d") }
        if hours > 0 { parts.append("\(hours) h") }
        return h > 0 ? "In \(parts.joined(separator: " "))" : "\(parts.joined(separator: " ")) ago"
    }
}

/// Search box with live results. Stays open so several cities can be added in a row.
struct AddCityField: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    @State private var query = SelfTest.isActive ? "lon" : ""
    @FocusState private var focused: Bool

    private var results: [CityEntry] { CityDirectory.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: ui.s) {
            HStack(spacing: ui.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textMuted)
                TextField("Add a city, airport code, PST, UTC+5…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = results.first { add(first) } }
                    .testID("search-field")
            }
            .font(ui.font(15))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, ui.m)
            .frame(height: ui.pt(44))
            .background(RoundedRectangle(cornerRadius: ui.pt(12), style: .continuous).fill(Palette.bg))
            .overlay(
                RoundedRectangle(cornerRadius: ui.pt(12), style: .continuous)
                    .strokeBorder(focused ? Palette.textFaint : .clear, lineWidth: 0.5)
            )

            if !store.canAdd {
                Text("You can track up to \(ZoneStore.maxPlaces) cities. Remove one in Edit to add another.")
                    .font(ui.meta)
                    .foregroundStyle(Palette.textMuted)
            } else if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            Button { add(entry) } label: {
                                HStack(spacing: ui.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(ui.body)
                                            .foregroundStyle(Palette.textPrimary)
                                        Text(entry.region.replacingOccurrences(of: "_", with: " "))
                                            .font(ui.meta)
                                            .foregroundStyle(Palette.textMuted)
                                    }
                                    Spacer()
                                    if let zone = TimeZone(identifier: entry.timeZoneID) {
                                        Text(TimeMath.time(store.now, in: zone, use24h: store.use24h))
                                            .font(ui.body)
                                            .foregroundStyle(Palette.textSecondary)
                                            .monospacedDigit()
                                        Text(TimeMath.offsetLabel(seconds: zone.secondsFromGMT(for: store.now)))
                                            .font(ui.meta)
                                            .foregroundStyle(Palette.textMuted)
                                            .frame(width: ui.pt(72), alignment: .trailing)
                                    }
                                    Image(systemName: store.contains(entry) ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(ui.font(17))
                                        .foregroundStyle(Palette.textMuted)
                                }
                                .padding(.horizontal, ui.m)
                                .frame(height: ui.pt(52))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowButtonStyle())
                            .disabled(store.contains(entry))
                            .help(store.contains(entry) ? "Already added" : "Add \(entry.name)")
                            .testID("result-\(index)")
                        }
                    }
                }
                .frame(maxHeight: ui.pt(168))   // about three results, so the strip stays in view
            }
        }
        .onAppear { focused = true }
    }

    private func add(_ entry: CityEntry) {
        guard store.canAdd else { return }
        withAnimation(.snappy) { store.add(entry) }
        query = ""
    }
}

// MARK: - Bits

/// Small in-app mark: warm-black tile, three ribbons and the white lens.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Palette.subtle)
            .overlay(
                VStack(spacing: size * 0.1) {
                    Capsule().fill(Palette.cream).frame(width: size * 0.62, height: size * 0.12)
                    Capsule().fill(Palette.textFaint).frame(width: size * 0.62, height: size * 0.12)
                    Capsule().fill(Palette.textMuted).frame(width: size * 0.62, height: size * 0.12)
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white, lineWidth: max(1.5, size * 0.06))
                    .frame(width: size * 0.26, height: size * 0.68)
            )
            .frame(width: size, height: size)
    }
}

struct IconButton: View {
    @Environment(\.metrics) private var ui
    let symbol: String
    let help: String
    var small = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ui.font(small ? 12 : 14, .semibold))
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: ui.pt(small ? 28 : 34), height: ui.pt(small ? 28 : 34))
                .background(Circle().fill(hovering ? Palette.borderStrong : Palette.border))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// apple.com-style pill: white for the primary action, warm grey for secondary.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, small: small)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let small: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(ui.font(small ? 13 : 14, .semibold))
                .padding(.horizontal, ui.pt(small ? 14 : 20))
                .frame(height: ui.pt(small ? 28 : 34))
                .foregroundStyle(prominent ? Palette.bg : (isEnabled ? Palette.textPrimary : Palette.textMuted))
                .background(
                    Capsule().fill(prominent ? (hovering ? Palette.cream : Color.white) : (hovering && isEnabled ? Palette.borderStrong : Palette.border))
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// Large rounded raised surface, like the product tiles on apple.com.
struct Tile<Content: View>: View {
    @Environment(\.metrics) private var ui
    /// Content that brings its own top spacing (the strip's overlap row) sets this to keep the
    /// tile's inner margins optically equal.
    var tightTop = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(ui.pt(20))
            .padding(.top, tightTop ? -ui.pt(12) : 0)
            .background(RoundedRectangle(cornerRadius: ui.pt(22), style: .continuous).fill(Palette.raisedTile))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowHover(configuration: configuration)
    }

    private struct RowHover: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: ui.pt(12), style: .continuous)
                        .fill(configuration.isPressed ? Palette.borderStrong : (hovering ? Palette.border : .clear))
                )
                .onHover { hovering = $0 }
        }
    }
}
