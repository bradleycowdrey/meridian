import SwiftUI

/// bradcowdrey.com design tokens (warm near-black, cream, crimson; Inter-like 400/500 weights),
/// plus the 8-pt spacing grid and type scale used across the app.
enum Palette {
    static let bg = Color(hex: 0x1A1816)
    static let raised = Color(hex: 0x1C1A18)
    static let subtle = Color(hex: 0x222018)
    static let border = Color(hex: 0x2A2520)
    static let textPrimary = Color.white
    static let cream = Color(hex: 0xFFF1E5)
    static let textSecondary = Color(hex: 0xE0D8D0)
    static let textMuted = Color(hex: 0xB0A898)
    static let textFaint = Color(hex: 0x807870)
    static let crimson = Color(hex: 0x990F3D)
    /// Raised tile surface and stronger hover fill, a step up from bg on the same warm scale.
    static let raisedTile = Color(hex: 0x23201D)
    static let borderStrong = Color(hex: 0x3A3530)
    /// Crimson lifted for legibility as text on dark (eyebrows), same hue as #990F3D.
    static let accent = Color(hex: 0xE04A7A)
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum TypeScale {
    // apple.com rhythm: semibold headlines, tight tracking, regular body.
    static let eyebrow = Font.system(size: 13, weight: .semibold)
    static let meta = Font.system(size: 13, weight: .regular)
    static let body = Font.system(size: 15, weight: .semibold)
    static let cell = Font.system(size: 17, weight: .medium)
    static let title = Font.system(size: 19, weight: .semibold)
    static let display = Font.system(size: 34, weight: .semibold)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
