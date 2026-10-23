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
    static let shareMessage = "Meridian: every time zone at a glance. Free, by Bradley Cowdrey."
}
