import SwiftUI
import AppKit

/// The whole app in one panel: header, the moment, ribbons. Used by both the
/// menu bar popover and the desktop window.
struct ClockPanel: View {
    @EnvironmentObject private var store: ZoneStore
    var compact = false

    var body: some View {
        let ui = Metrics(scale: store.uiSize.scale, family: store.appFont)
        ClockPanelContent(compact: compact)
            .environment(\.metrics, ui)
    }
}

private struct ClockPanelContent: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui
    let compact: Bool
    @State private var adding = false
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // bradcowdrey.com's signature crimson rule.
            Palette.crimson.frame(height: 3)

            VStack(alignment: .leading, spacing: ui.xl) {
                header
                UpdateBanner()
                TravelBar()

                if adding || store.places.isEmpty {
                    Tile { AddCityField() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !store.places.isEmpty {
                    Tile(tightTop: true) {
                        StripView(
                            cellWidth: ui.cellWidth(compact: compact),
                            rowHeight: ui.rowHeight(compact: compact),
                            labelWidth: ui.labelWidth(compact: compact),
                            editing: editing
                        )
                    }
                }

                Link(destination: Brand.website) {
                    Text("\(Brand.author) · \(Brand.websiteHost)")
                }
                .font(ui.font(12))
                .foregroundStyle(Palette.textMuted)
            }
            .padding(ui.xl)
        }
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
        .onAppear { store.tick() }
        .focusable()
        .focusEffectDisabled()
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

    private var header: some View {
        HStack(spacing: ui.m) {
            AppMark(size: ui.pt(28))
            Text(Brand.appName)
                .font(ui.title)
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(editing ? "Done" : "Edit") {
                withAnimation(.snappy) { editing.toggle(); if editing { adding = false } }
            }
            .buttonStyle(PillButtonStyle(prominent: editing))
            .disabled(store.places.isEmpty)
            .help("Remove or reorder cities")
            Button(adding ? "Done" : "Add") {
                withAnimation(.snappy) { adding.toggle(); if adding { editing = false } }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(!store.canAdd && !adding)
            .help(store.canAdd ? "Add a city" : "You can track up to \(ZoneStore.maxPlaces) cities")
            MoreMenu(compact: compact)
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

    var body: some View {
        Menu {
            if let release = updater.latest {
                Button("Install Meridian \(release.version)…") { Task { await updater.install() } }
                    .disabled(updater.isBusy)
                Divider()
            }
            Button("Copy This Moment") { store.copyMoment() }
            Divider()
            Picker("Size", selection: $store.uiSize) {
                ForEach(UISize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $store.appFont) {
                ForEach(AppFont.allCases) { Text($0.label).tag($0) }
            }
            Button("Larger  ⌘+") { store.stepSize(1) }
                .disabled(store.uiSize.larger == nil)
            Button("Smaller  ⌘−") { store.stepSize(-1) }
                .disabled(store.uiSize.smaller == nil)
            Divider()
            if compact {
                Button("Open as Window") {
                    openWindow(id: "strip")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                .disabled(updater.isBusy || !updater.canSelfUpdate)
            Divider()
            Button("Quit Meridian") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(ui.font(14, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: ui.pt(34), height: ui.pt(34))
                .background(Circle().fill(Palette.border))
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
        if let release = updater.latest {
            HStack(spacing: ui.m) {
                Circle().fill(Palette.crimson).frame(width: ui.pt(7), height: ui.pt(7))
                Text("Meridian \(release.version) is available")
                    .font(ui.font(14, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("You have \(updater.currentVersion)")
                    .font(ui.meta)
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: ui.s)
                switch updater.phase {
                case .downloading:
                    ProgressView().controlSize(.small)
                    Text("Downloading…").font(ui.meta).foregroundStyle(Palette.textMuted)
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("Installing…").font(ui.meta).foregroundStyle(Palette.textMuted)
                default:
                    Button("Update") { Task { await updater.install() } }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .padding(.leading, ui.l)
            .padding(.trailing, ui.s)
            .padding(.vertical, ui.s)
            .background(Capsule().fill(Palette.raisedTile))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The moment you're looking at, apple.com-style, and the travel controls.
struct TravelBar: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.metrics) private var ui

    var body: some View {
        let moment = store.selectedMoment()
        HStack(alignment: .bottom, spacing: ui.m) {
            VStack(alignment: .leading, spacing: ui.xs) {
                HStack(spacing: ui.pt(6)) {
                    if store.offsetHours == 0 {
                        Circle().fill(Palette.crimson).frame(width: ui.pt(7), height: ui.pt(7))
                    }
                    Text(relativeLabel)
                        .font(ui.eyebrow)
                        .foregroundStyle(store.offsetHours == 0 ? Palette.textMuted : Palette.cream)
                }
                Text(TimeMath.fullMoment(moment, in: .current, use24h: store.use24h))
                    .font(ui.display)
                    .tracking(-0.9 * ui.scale)
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: ui.m)
            HStack(spacing: ui.s) {
                IconButton(symbol: "chevron.left", help: "One hour earlier") { store.travel(-1) }
                Button("Now") { store.backToNow() }
                    .buttonStyle(PillButtonStyle(prominent: store.offsetHours != 0))
                    .disabled(store.offsetHours == 0)
                IconButton(symbol: "chevron.right", help: "One hour later") { store.travel(1) }
            }
        }
        .animation(.snappy, value: store.offsetHours)
    }

    private var relativeLabel: String {
        let h = store.offsetHours
        if h == 0 { return "Now, your time" }
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
    @State private var query = ""
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
            }
            .font(ui.font(15))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, ui.m)
            .frame(height: ui.pt(44))
            .background(RoundedRectangle(cornerRadius: ui.pt(12), style: .continuous).fill(Palette.bg))
            .overlay(
                RoundedRectangle(cornerRadius: ui.pt(12), style: .continuous)
                    .strokeBorder(focused ? Palette.textFaint : .clear, lineWidth: 1)
            )

            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { entry in
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
                                    Image(systemName: "plus.circle.fill")
                                        .font(ui.font(17))
                                        .foregroundStyle(Palette.textMuted)
                                }
                                .padding(.horizontal, ui.m)
                                .frame(height: ui.pt(52))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }
                .frame(maxHeight: ui.pt(240))
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ui.font(14, .semibold))
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: ui.pt(34), height: ui.pt(34))
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

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.metrics) private var ui
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(ui.font(14, .semibold))
                .padding(.horizontal, ui.pt(20))
                .frame(height: ui.pt(34))
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
