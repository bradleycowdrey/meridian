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
    static let cream = WidgetTone.cream
    static let crimson = WidgetTone.crimson

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

/// City cards on the main screen.
enum Card {
    static let margin: CGFloat = 16
    static let padding: CGFloat = 16
    static let gap: CGFloat = 12
    static let radius: CGFloat = 16
}

/// A quiet sky behind each card, as in Two Degrees but only a touch: a soft wash at the top for
/// the sky where the city is at the moment shown (night, dawn or dusk, day), fading into the card's
/// own colour by the bottom so text and the day bar read exactly as before.
enum CardSky {
    enum Phase: Equatable { case night, twilight, day }

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

    static func top(_ phase: Phase) -> Color {
        switch phase {
        case .night: return Color(red: 0x1B / 255, green: 0x1F / 255, blue: 0x30 / 255)     // deep indigo
        case .twilight: return Color(red: 0x3A / 255, green: 0x27 / 255, blue: 0x22 / 255)  // ember
        case .day: return Color(red: 0x2C / 255, green: 0x35 / 255, blue: 0x40 / 255)       // slate sky
        }
    }

    static func gradient(for place: Place, at date: Date) -> LinearGradient {
        LinearGradient(colors: [top(phase(for: place, at: date)), Theme.tile], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.85))
    }
}
