import SwiftUI
import AppKit
import CoreText

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

/// The two typefaces: the Mac's own SF Pro, or Inter to match bradcowdrey.com.
enum AppFont: String, CaseIterable, Identifiable {
    case system, inter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System (SF Pro)"
        case .inter: return "Inter (bradcowdrey.com)"
        }
    }
}

/// Registers the Inter files bundled in Contents/Resources/Fonts for this process only.
enum FontRegistry {
    private(set) static var interAvailable = false

    static func registerBundledFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
        interAvailable = NSFont(name: "Inter-Regular", size: 12) != nil
    }
}

/// Size-aware design tokens: an 8-pt spacing grid and an apple.com-style type scale.
struct Metrics {
    let scale: CGFloat
    var family: AppFont = .system

    func pt(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }

    /// A font at a scaled size in the chosen family. Inter falls back to SF if it isn't bundled.
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let points = pt(size)
        guard family == .inter, FontRegistry.interAvailable else { return .system(size: points, weight: weight) }
        let face: String
        switch weight {
        case .semibold, .bold, .heavy, .black: face = "Inter-SemiBold"
        case .medium: face = "Inter-Medium"
        default: face = "Inter-Regular"
        }
        return .custom(face, fixedSize: points)
    }

    // Spacing grid
    var xs: CGFloat { pt(4) }
    var s: CGFloat { pt(8) }
    var m: CGFloat { pt(12) }
    var l: CGFloat { pt(16) }
    var xl: CGFloat { pt(24) }

    // Type scale: semibold headlines, tight tracking, regular body
    var eyebrow: Font { font(13, .semibold) }
    var meta: Font { font(13) }
    var body: Font { font(15, .semibold) }
    var cell: Font { font(17, .medium) }
    var cellNow: Font { font(17, .semibold) }
    var title: Font { font(19, .semibold) }
    var display: Font { font(34, .semibold) }

    // Strip geometry: one even gutter in both directions; the "now" lens's 2pt stroke sits
    // exactly centred in that gutter, and its corners are concentric with the tiles'.
    var gutter: CGFloat { 2 * pt(4) }                    // always even: 6 / 8 / 8 / 8 / 10
    var tileRadius: CGFloat { pt(10) }
    let lensStroke: CGFloat = 2
    var lensOutset: CGFloat { gutter / 2 + lensStroke / 2 }  // stroke centre on the gutter's midline
    var lensRadius: CGFloat { tileRadius + lensOutset }      // concentric with the tile corners
    func tileWidth(compact: Bool) -> CGFloat { pt(compact ? 42 : 46) }
    func cellWidth(compact: Bool) -> CGFloat { tileWidth(compact: compact) + gutter }   // column pitch
    func rowHeight(compact: Bool) -> CGFloat { pt(compact ? 44 : 48) }
    func labelWidth(compact: Bool) -> CGFloat { pt(compact ? 152 : 176) }
    var tilePadding: CGFloat { pt(20) }

    /// Panel width built from its parts, so the strip always shows whole hour columns:
    /// 7 in the menu bar popover, 11 in the window. If that wouldn't fit on screen at this
    /// size, drop two columns at a time (keeping one centred "now" column).
    func panelWidth(compact: Bool, screenWidth: CGFloat) -> CGFloat {
        func width(_ columns: Int) -> CGFloat {
            2 * xl + 2 * tilePadding + labelWidth(compact: compact) + CGFloat(columns) * cellWidth(compact: compact)
        }
        var columns = compact ? 7 : 11
        while columns > 5 && width(columns) > screenWidth { columns -= 2 }
        return width(columns)
    }
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
