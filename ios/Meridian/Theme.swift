import SwiftUI

/// bradcowdrey.com colours (shared with the widgets through WidgetTone) and links.
enum Theme {
    static let bg = WidgetTone.bg
    static let tile = Color(red: 0x23 / 255, green: 0x20 / 255, blue: 0x1D / 255)
    static let border = Color(red: 0x3A / 255, green: 0x35 / 255, blue: 0x30 / 255)
    static let primary = WidgetTone.primary
    static let secondary = WidgetTone.secondary
    static let muted = WidgetTone.muted
    static let faint = WidgetTone.faint
    /// Widgets and the Terms "I Agree" capsule only; the rest of the app is white, as in Two Degrees.
    static let cream = WidgetTone.cream
    /// Widgets and the app icon only.
    static let crimson = WidgetTone.crimson

    /// A colour from 0xRRGGBB (the iOS app has no `Color(hex:)`).
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }

    /// Clock-change notices.
    static let notice = rgb(0xF2A65A)
    static let sun = rgb(0xF4B860)
    static let moon = rgb(0xE9DCC8)
    /// The calendar's selected day (the clear-day sky).
    static let pickerAccent = rgb(0x3D74B0)
    /// Switches, which would be white (and lose their knob) under the app's white tint.
    static let switchOn = rgb(0x30D158)

    /// White on dark, in steps.
    enum Op {
        static let strong = 0.9
        static let body = 0.85
        static let label = 0.8
        static let sub = 0.7
        static let caption = 0.6
        static let faint = 0.35
        static let track = 0.15
        static let fill = 0.12
        static let rowFill = 0.07
    }

    static let website = URL(string: "https://bradcowdrey.com")!
    static let appPage = URL(string: "https://bradcowdrey.com/meridian")!
    static let legal = URL(string: "https://bradcowdrey.com/legal")!
    static let source = URL(string: "https://github.com/bradleycowdrey/meridian")!
    static let issues = URL(string: "https://github.com/bradleycowdrey/meridian/issues")!
    static let macDownload = URL(string: "https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian.dmg")!
    /// What Share says, as Two Degrees does: the app, what it does here, who made it.
    static let shareMessage = "Meridian: every time zone at a glance, on your iPhone and its Home Screen and Lock Screen. Free, by Bradley Cowdrey."
    /// Copy a Message to Send: ready to paste into a chat, with where to get it.
    static let messageToSend = "\(shareMessage)\n\nGet it for iPhone, Mac or Android: \(appPage.absoluteString)"
}

/// City cards on the main screen, and the cards on the sheets.
enum Card {
    static let radius: CGFloat = 16
    static let padding: CGFloat = 14
    static let gap: CGFloat = 10
    static let margin: CGFloat = 16
}

/// The sky behind each card, as in Two Degrees: a full-height gradient for the sky where the city
/// is at the moment shown (night, dawn or dusk, day).
enum Sky {
    enum Phase: Hashable { case night, twilight, day }

    /// Within an hour of sunrise or sunset is twilight.
    static func phase(for place: Place, at date: Date) -> Phase {
        switch Sun.phase(place, at: date) {
        case .day(let sets)?: return sets.timeIntervalSince(date) < 3600 ? .twilight : .day
        case .night(let rises)?: return rises.timeIntervalSince(date) < 3600 ? .twilight : .night
        case .allDay?: return .day
        case .allNight?: return .night
        case nil:
            let hour = place.calendar.component(.hour, from: date)
            return (7..<19).contains(hour) ? .day : .night
        }
    }

    /// Two Degrees' clear day, partly cloudy day and clear night.
    static func colors(_ phase: Phase) -> (top: Color, bottom: Color) {
        switch phase {
        case .day: return (Theme.rgb(0x3D74B0), Theme.rgb(0x1C3A5E))
        case .twilight: return (Theme.rgb(0x4F78A3), Theme.rgb(0x24384F))
        case .night: return (Theme.rgb(0x141E3C), Theme.rgb(0x0A0E1C))
        }
    }

    static func gradient(_ phase: Phase) -> LinearGradient {
        let sky = colors(phase)
        return LinearGradient(colors: [sky.top, sky.bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// A card's sky; crossfades when the phase changes.
struct SkyView: View {
    let phase: Sky.Phase

    var body: some View {
        ZStack {
            Sky.gradient(phase)
                .id(phase)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.6), value: phase)
    }
}

/// A clock reading: digits, with AM or PM small and raised beside them (none in 24-hour time).
enum ClockText {
    static func text(_ digits: String, suffix: String?, size: CGFloat, weight: Font.Weight) -> Text {
        let main = Text(digits).font(.system(size: size, weight: weight)).monospacedDigit()
        guard let suffix else { return main }
        let small = Text("\u{2009}" + suffix)
            .font(.system(size: size * 0.42, weight: .medium))
            .baselineOffset(size * 0.36)
        return Text("\(main)\(small)")
    }

    /// "9:41" and "AM", or "09:41" and nil.
    static func parts(hour: Int, minute: Int, use24h: Bool) -> (digits: String, suffix: String?) {
        if use24h { return (String(format: "%02d:%02d", hour, minute), nil) }
        return ("\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))", hour < 12 ? "AM" : "PM")
    }
}

/// A card's caption, as in Two Degrees: a small icon and an uppercase title.
struct CardCaption: View {
    let title: String
    let symbol: String

    init(_ title: String, _ symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title.uppercased(), systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(Theme.Op.caption))
    }
}

/// A choice as a capsule: white when on, faint white when off.
struct PillChip: View {
    let title: String
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(Theme.Op.fill)))
            .foregroundStyle(isOn ? Color.black : Color.white)
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    /// A card on a sheet: frosted, rounded, full width.
    func glassCard(padding: CGFloat = Card.padding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Card.radius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }

    /// A form section's rows: a faint white fill on the sheet's background.
    func meridianSection() -> some View {
        listRowBackground(Color.white.opacity(Theme.Op.rowFill))
    }

    /// A form on the sheet's background, with white controls. Toggles take `Theme.switchOn` and
    /// graphical date pickers `Theme.pickerAccent`, so neither turns white on white.
    func meridianForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(.white)
    }
}
