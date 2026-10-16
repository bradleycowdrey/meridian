import SwiftUI
import AppKit

/// The whole app in one panel: header, time-travel bar, ribbons. Used by both the
/// menu bar popover and the desktop window.
struct ClockPanel: View {
    @EnvironmentObject private var store: ZoneStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var compact = false
    @State private var adding = false
    @State private var editing = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header

            // Hero: the moment you're looking at, apple.com-style headline.
            TravelBar(copied: $copied)

            if adding || store.places.isEmpty {
                Tile { AddCityField() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !store.places.isEmpty {
                Tile {
                    StripView(
                        cellWidth: compact ? 48 : 52,
                        rowHeight: compact ? 44 : 48,
                        labelWidth: compact ? 160 : 176,
                        editing: editing
                    )
                }
            }

            footer
        }
        .padding(compact ? Space.xl : Space.xl + Space.s)
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
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            AppMark(size: 28)
            Text(Brand.appName)
                .font(TypeScale.title)
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
            if compact {
                IconButton(symbol: "macwindow", help: "Open as a desktop window") {
                    openWindow(id: "strip")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            IconButton(symbol: "gearshape", help: "Settings") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Space.l) {
            Link(destination: Brand.website) {
                Text("\(Brand.author) · \(Brand.websiteHost)")
            }
            .foregroundStyle(Palette.textFaint)
            Spacer()
            Text(editing ? "Drag ≡ to reorder" : "Drag, scroll or ← → to travel")
                .foregroundStyle(Palette.textFaint)
            if compact {
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textFaint)
            }
        }
        .font(.system(size: 12))
    }
}

/// "Now" / "In 3 h" with the moment in your own zone, and the travel controls.
struct TravelBar: View {
    @EnvironmentObject private var store: ZoneStore
    @Binding var copied: Bool

    var body: some View {
        let moment = store.selectedMoment()
        HStack(alignment: .bottom, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(relativeLabel)
                    .font(TypeScale.eyebrow)
                    .foregroundStyle(store.offsetHours == 0 ? Palette.accent : Palette.cream)
                Text(TimeMath.fullMoment(moment, in: .current, use24h: store.use24h))
                    .font(TypeScale.display)
                    .tracking(-0.9)
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: Space.s) {
                IconButton(symbol: "chevron.left", help: "One hour earlier") { store.travel(-1) }
                Button("Now") { store.backToNow() }
                    .buttonStyle(PillButtonStyle(prominent: store.offsetHours != 0))
                    .disabled(store.offsetHours == 0)
                IconButton(symbol: "chevron.right", help: "One hour later") { store.travel(1) }
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy this moment for every city") {
                    store.copyMoment()
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { copied = false }
                    }
                }
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
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [CityEntry] { CityDirectory.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textFaint)
                TextField("Add a city, airport code, PST, UTC+5…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = results.first { add(first) } }
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.bg))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Palette.textFaint : .clear, lineWidth: 1)
            )

            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { entry in
                            Button { add(entry) } label: {
                                HStack(spacing: Space.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(TypeScale.body)
                                            .foregroundStyle(Palette.textPrimary)
                                        Text(entry.region.replacingOccurrences(of: "_", with: " "))
                                            .font(TypeScale.meta)
                                            .foregroundStyle(Palette.textFaint)
                                    }
                                    Spacer()
                                    if let zone = TimeZone(identifier: entry.timeZoneID) {
                                        Text(TimeMath.time(store.now, in: zone, use24h: store.use24h))
                                            .font(TypeScale.body)
                                            .foregroundStyle(Palette.textSecondary)
                                            .monospacedDigit()
                                        Text(TimeMath.offsetLabel(seconds: zone.secondsFromGMT(for: store.now)))
                                            .font(TypeScale.meta)
                                            .foregroundStyle(Palette.textFaint)
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(Palette.textMuted)
                                }
                                .padding(.horizontal, Space.m)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }
                .frame(maxHeight: 240)
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

/// Small in-app mark: warm-black tile, cream ribbon and the white lens.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Palette.subtle)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
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
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? Palette.textPrimary : Palette.textMuted)
                .frame(width: 34, height: 34)
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
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, Space.l + Space.xs)
                .frame(height: 34)
                .foregroundStyle(prominent ? Palette.bg : (isEnabled ? Palette.textPrimary : Palette.textFaint))
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Space.l + Space.xs)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.raisedTile))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowHover(configuration: configuration)
    }

    private struct RowHover: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(configuration.isPressed ? Palette.borderStrong : (hovering ? Palette.border : .clear))
                )
                .onHover { hovering = $0 }
        }
    }
}
