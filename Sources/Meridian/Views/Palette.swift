import SwiftUI
import AppKit
import CoreText

/// Two Degrees design tokens, as on iPhone: black and near-black surfaces, white text at four
/// strengths, white hairlines, and a handful of status colours. Plus the 8-pt spacing grid and
/// type scale used across the app.
enum Palette {
    static let bg = Color(hex: 0x0B0C0F)
    static let raised = Color(hex: 0x0B0C0F)
    static let subtle = Color(hex: 0x111317)
    /// Hover fills and quiet secondary fills.
    static let border = Color.white.opacity(0.12)
    static let textPrimary = Color.white
    /// The emphasis tone (active segment, Now label, all-working mark). White in this palette;
    /// the name is kept from the earlier one.
    static let cream = Color.white
    static let textSecondary = Color.white.opacity(0.85)
    /// 7.3:1 on bg.
    static let textMuted = Color.white.opacity(0.6)
    /// 4.6:1 on bg and raisedTile. Never on a photo.
    static let textFaint = Color.white.opacity(0.46)
    /// Raised tile surface, a step up from bg.
    static let raisedTile = Color(hex: 0x111317)
    /// Hairlines, and pressed or stronger hover fills.
    static let borderStrong = Color.white.opacity(0.2)
    /// Search field fill.
    static let field = Color.black
    /// Search-result hover and pressed fill.
    static let menu = Color(hex: 0x1E1E22)
    /// The "Now" dot; status Working.
    static let now = Color(hex: 0x9AD3A8)
    /// Update-available dot.
    static let accent = Color(hex: 0x8CC0F5)
    /// Midnight mark; status Weekend and Day off.
    static let midnight = Color(hex: 0xF2C66D)
    /// Status Off hours.
    static let offHours = Color(hex: 0xD9DEE6)
    /// Status for a public holiday; error notices.
    static let holiday = Color(hex: 0xF39A72)
    /// Edit mode's remove button.
    static let destructive = Color(red: 1, green: 0.27, blue: 0.23)
    /// Photo scrims and the plates behind pills.
    static let scrim = Color.black
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
        // Legibility floor: nothing is set under 11 pt, at any interface size.
        let points = max(11, pt(size))
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
    var cellNow: Font { font(19, .semibold) }
    var title: Font { font(19, .semibold) }
    var display: Font { font(34, .semibold) }

    // Strip geometry: one even gutter in both directions. The selected ("Now") tile is drawn
    // larger than the rest, and one outline runs down every row around those tiles: concentric
    // with them, its line midway in the clear gap between a Now tile and its neighbour.
    var gutter: CGFloat { 2 * pt(4) }                    // always even: 6 / 8 / 8 / 8 / 10
    var tileRadius: CGFloat { pt(10) }
    let nowScale: CGFloat = 1.13
    func tileWidth(compact: Bool) -> CGFloat { pt(compact ? 42 : 46) }
    func cellWidth(compact: Bool) -> CGFloat { tileWidth(compact: compact) + gutter }   // column pitch
    func labelWidth(compact: Bool) -> CGFloat { pt(compact ? 184 : 200) }
    /// The tall (preferred) row: time, city, and a line for the zone and status.
    func rowHeight(compact: Bool) -> CGFloat { pt(compact ? 80 : 84) }
    /// The shortest a row gets: two lines of label.
    func rowHeightShort(compact: Bool) -> CGFloat { pt(compact ? 56 : 58) }
    /// Rows share the body's height: tall when they fit, never under short (then the body scrolls).
    func rowHeight(compact: Bool, rows: Int, room: CGFloat) -> CGFloat {
        guard rows > 0 else { return rowHeight(compact: compact) }
        let fit = (room / CGFloat(rows)).rounded(.down) - gutter
        return min(rowHeight(compact: compact), max(rowHeightShort(compact: compact), fit))
    }
    /// Rows this tall or taller use the three-line label.
    var threeLineRow: CGFloat { pt(76) }
    func tileHeight(row: CGFloat) -> CGFloat { min(pt(52), row - pt(14)) }
    /// Space under the tiles inside a row.
    func tileBottom(row: CGFloat) -> CGFloat { row >= threeLineRow ? pt(10) : pt(7) }
    /// How far a row's photo card reaches beyond the row's content on each side.
    var cardOutset: CGFloat { pt(8) }
    var cardRadius: CGFloat { pt(14) }

    // The Now outline.
    /// How far the Now tile grows past its cell on each side.
    func nowGrowX(tile: CGFloat) -> CGFloat { tile * (nowScale - 1) / 2 }
    /// From the Now tile's edge to the outline's centre line: midway in the clear gap.
    func lensInset(tile: CGFloat) -> CGFloat { (gutter - nowGrowX(tile: tile)) / 2 }
    var lensCore: CGFloat { gutter >= 8 ? 2 : 1.5 }
    var lensEdge: CGFloat { gutter >= 8 ? 1 : 0.5 }
    /// Concentric with the Now tile's corners.
    func lensRadius(tile: CGFloat) -> CGFloat { tileRadius * nowScale + lensInset(tile: tile) }
    var tilePadding: CGFloat { pt(20) }

    /// Hours shown: two before, now, two after.
    static let visibleColumns = 5

    /// Panel width built from its parts: the room of seven standard hour columns (in the menu
    /// bar popover and the window alike), or five if that wouldn't fit on screen at this size.
    func panelWidth(compact: Bool, screenWidth: CGFloat) -> CGFloat {
        func width(_ columns: Int) -> CGFloat {
            2 * xl + 2 * tilePadding + labelWidth(compact: compact) + CGFloat(columns) * cellWidth(compact: compact)
        }
        return width(7) > screenWidth ? width(5) : width(7)
    }

    /// The column pitch actually used: the strip's room shared by the five visible hours, so
    /// fewer, wider tiles fill the same panel. Whole points keep the edges crisp.
    func stripCellWidth(compact: Bool, screenWidth: CGFloat) -> CGFloat {
        let strip = panelWidth(compact: compact, screenWidth: screenWidth) - 2 * xl - 2 * tilePadding - labelWidth(compact: compact)
        return (strip / CGFloat(Self.visibleColumns)).rounded(.down)
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
