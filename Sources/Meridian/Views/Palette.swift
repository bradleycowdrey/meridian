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
}

/// The five interface sizes. Everything (type, cells, spacing, popover width) scales together,
/// rounded to whole points so edges stay crisp.
enum UISize: String, CaseIterable, Identifiable {
    case extraSmall, small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .extraSmall: return 0.82
        case .small: return 0.91
        case .medium: return 1.0
        case .large: return 1.12
        case .extraLarge: return 1.26
        }
    }

    var smaller: UISize? { UISize.allCases.firstIndex(of: self).flatMap { $0 > 0 ? UISize.allCases[$0 - 1] : nil } }
    var larger: UISize? { UISize.allCases.firstIndex(of: self).flatMap { $0 < UISize.allCases.count - 1 ? UISize.allCases[$0 + 1] : nil } }
}

/// Size-aware design tokens: an 8-pt spacing grid and an apple.com-style type scale.
struct Metrics {
    let scale: CGFloat

    func pt(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }

    // Spacing grid
    var xs: CGFloat { pt(4) }
    var s: CGFloat { pt(8) }
    var m: CGFloat { pt(12) }
    var l: CGFloat { pt(16) }
    var xl: CGFloat { pt(24) }

    // Type scale: semibold headlines, tight tracking, regular body
    var eyebrow: Font { .system(size: pt(13), weight: .semibold) }
    var meta: Font { .system(size: pt(13), weight: .regular) }
    var body: Font { .system(size: pt(15), weight: .semibold) }
    var cell: Font { .system(size: pt(17), weight: .medium) }
    var cellNow: Font { .system(size: pt(17), weight: .semibold) }
    var title: Font { .system(size: pt(19), weight: .semibold) }
    var display: Font { .system(size: pt(34), weight: .semibold) }

    // Strip geometry
    func cellWidth(compact: Bool) -> CGFloat { pt(compact ? 46 : 52) }
    func rowHeight(compact: Bool) -> CGFloat { pt(compact ? 44 : 48) }
    func labelWidth(compact: Bool) -> CGFloat { pt(compact ? 152 : 176) }
    var popoverWidth: CGFloat { pt(600) }
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = Metrics(scale: 1)
}

extension EnvironmentValues {
    var metrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
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
