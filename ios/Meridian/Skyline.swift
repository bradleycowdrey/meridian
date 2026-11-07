import SwiftUI
import UIKit

/// The city cards: each city a rounded card on the warm dark background, a skyline banner across
/// its top (the city's photo, or a skyline drawn for it) with its time on it, and under that its
/// name, time zone and working status on the left and its five hour tiles on the right.
enum RowCard {
    static let radius: CGFloat = 16
    /// Between cards, and above the first and below the last.
    static let gap: CGFloat = 8
    /// A card's height once the list scrolls (six or more cities).
    static let scrollHeight: CGFloat = 132
    /// Up to this many cities share the screen's height; more scroll.
    static let maxFitCount = 5
    /// Shorter than this, the cards stop sharing the screen and scroll at `scrollHeight`.
    static let minFitHeight: CGFloat = 96
    /// The hour tiles' height under the banner (less when the card is short).
    static let tileHeight: CGFloat = 52

    /// A tall card gets the large time and the status detail.
    static func isTall(_ row: CGFloat) -> Bool { row >= 150 }

    static func bannerHeight(_ row: CGFloat) -> CGFloat {
        (isTall(row) ? row * 0.42 : max(42, row * 0.34)).rounded()
    }
}

/// The skyline photos bundled with the app, by city, and their credits.
enum SkylineArt {
    /// Sky.phase, widened so the hour after sunrise and the hour after sunset are twilight too.
    static func phase(for place: Place, at date: Date) -> Sky.Phase {
        let now = Sky.phase(for: place, at: date)
        let hourAgo = Sky.phase(for: place, at: date.addingTimeInterval(-3600))
        return (now != .twilight && hourAgo != now) ? .twilight : now
    }

    struct Credit {
        let city: String
        let file: String
        let url: URL
    }

    /// From Resources/Data/skyline-credits.json.
    static let credits: [Credit] = [
        Credit(city: "San Francisco", file: "San Francisco skyline from Coit Tower",
               url: URL(string: "https://commons.wikimedia.org/wiki/File:San_Francisco_skyline_from_Coit_Tower.jpg")!),
        Credit(city: "New York", file: "Manhattan from Weehawken, NJ",
               url: URL(string: "https://commons.wikimedia.org/wiki/File:Manhattan_from_Weehawken,_NJ.jpg")!),
        Credit(city: "London", file: "London Skyline (125508655)",
               url: URL(string: "https://commons.wikimedia.org/wiki/File:London_Skyline_(125508655).jpeg")!),
        Credit(city: "Tokyo", file: "Skyscrapers of Shinjuku 2009 January",
               url: URL(string: "https://commons.wikimedia.org/wiki/File:Skyscrapers_of_Shinjuku_2009_January.jpg")!),
    ]

    /// The photo's key for a city name ("San Francisco" -> "sanfrancisco"), or nil.
    static func key(for name: String) -> String? {
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "san francisco": return "sanfrancisco"
        case "new york", "new york city", "manhattan": return "newyork"
        case "london": return "london"
        case "tokyo": return "tokyo"
        default: return nil
        }
    }

    /// The bundled photo for a city (asset "Skyline-<key>"), or nil to draw one.
    static func photo(for name: String) -> UIImage? {
        key(for: name).flatMap { UIImage(named: "Skyline-\($0)") }
    }

    /// The photo shaded for the time of day there: darker and cooler at night, warmer and a
    /// little darker in twilight, as it is by day.
    static func shade(_ phase: Sky.Phase) -> Color {
        switch phase {
        case .night: return Color(red: 0.42, green: 0.45, blue: 0.55)
        case .twilight: return Color(red: 0.95, green: 0.84, blue: 0.72)
        case .day: return .white
        }
    }

    static func saturation(_ phase: Sky.Phase) -> Double {
        switch phase {
        case .night: return 0.75
        case .twilight: return 1.1
        case .day: return 1
        }
    }

    /// The drawn skyline's sky, top to bottom.
    static func sky(_ phase: Sky.Phase) -> [Color] {
        switch phase {
        case .day: return [Theme.rgb(0x4A80BD), Theme.rgb(0xA9CBEA)]
        case .twilight: return [Theme.rgb(0x2B3A6B), Theme.rgb(0xF08A5D)]
        case .night: return [Theme.rgb(0x0B1022), Theme.rgb(0x1A2340)]
        }
    }

    /// The drawn buildings' colour.
    static func ink(_ phase: Sky.Phase) -> Color {
        switch phase {
        case .day: return Theme.rgb(0x22324A)
        case .twilight: return Theme.rgb(0x1A1A2A)
        case .night: return Theme.rgb(0x06080F)
        }
    }
}

/// The same "random" numbers every time for the same city name, so its drawn skyline stays put.
struct SeededRandom {
    private var x: UInt32

    init(_ seed: String) {
        var v: UInt32 = 0
        for u in seed.unicodeScalars { v = v &* 31 &+ UInt32(truncatingIfNeeded: u.value) }
        x = v
    }

    mutating func next() -> CGFloat {
        x = x &* 1_664_525 &+ 1_013_904_223
        return CGFloat(x) / 4_294_967_296
    }
}

/// The banner across a card's top: the city's photo (filling it, shaded for the time of day
/// there), or a skyline drawn for it on that time of day's sky.
struct SkylineBanner: View {
    let place: Place
    let phase: Sky.Phase

    var body: some View {
        Color.clear
            .overlay { art }
            .clipped()
            .animation(.easeInOut(duration: 0.6), value: phase)
    }

    @ViewBuilder private var art: some View {
        if let photo = SkylineArt.photo(for: place.name) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .saturation(SkylineArt.saturation(phase))
                .colorMultiply(SkylineArt.shade(phase))
        } else {
            DrawnSkyline(seed: place.name, phase: phase)
        }
    }
}

/// A skyline drawn in code: buildings of the city's own (seeded) heights, lit windows after dark,
/// the sun or moon, on the sky for the time of day.
struct DrawnSkyline: View {
    let seed: String
    let phase: Sky.Phase

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let sky = SkylineArt.sky(phase)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // The sun, or the moon, or the setting sun low on the horizon.
        let glowCenter: CGPoint
        let glowRadius: CGFloat
        let glowColor: Color
        switch phase {
        case .night:
            glowCenter = CGPoint(x: w * 0.86, y: h * 0.28); glowRadius = 9; glowColor = Theme.rgb(0xF4F1E6).opacity(0.9)
        case .twilight:
            glowCenter = CGPoint(x: w * 0.88, y: h * 0.82); glowRadius = 22; glowColor = Theme.rgb(0xFFC27A).opacity(0.85)
        case .day:
            glowCenter = CGPoint(x: w * 0.86, y: h * 0.25); glowRadius = 12; glowColor = Theme.rgb(0xFFF6D8).opacity(0.95)
        }
        let halo = glowRadius * 2.2
        context.fill(Path(ellipseIn: CGRect(x: glowCenter.x - halo, y: glowCenter.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [glowColor.opacity(0.35), glowColor.opacity(0)]),
                                           center: glowCenter, startRadius: glowRadius, endRadius: halo))
        context.fill(Path(ellipseIn: CGRect(x: glowCenter.x - glowRadius, y: glowCenter.y - glowRadius,
                                            width: glowRadius * 2, height: glowRadius * 2)),
                     with: .color(glowColor))

        // Windows draw from their own generator so the buildings never change with the phase.
        var lights = SeededRandom(seed + "|windows")
        let ink = SkylineArt.ink(phase)
        let windowChance: CGFloat = phase == .night ? 0.35 : (phase == .twilight ? 0.18 : 0)
        let layout = Self.layout(seed: seed, size: size)

        // The front row of buildings, and their lit windows.
        var front = Path()
        var windows = Path()
        for rect in layout.front {
            front.addRect(rect)
            if windowChance > 0 {
                var y = rect.minY + 4
                while y < h - 3 {
                    var wx = rect.minX + 2
                    while wx < rect.maxX - 2 {
                        if lights.next() < windowChance { windows.addRect(CGRect(x: wx, y: y, width: 1.6, height: 2)) }
                        wx += 4
                    }
                    y += 5
                }
            }
        }

        // A paler row behind.
        var back = Path()
        for rect in layout.back { back.addRect(rect) }

        context.fill(back, with: .color(ink.opacity(0.55)))
        context.fill(front, with: .color(ink))
        context.fill(windows, with: .color(Theme.rgb(0xFFD98A).opacity(0.8)))
    }

    /// The buildings for a city's seed at a size: the front row left to right, and the paler row
    /// behind. The same every time for the same seed and size.
    static func layout(seed: String, size: CGSize) -> (front: [CGRect], back: [CGRect]) {
        let w = size.width, h = size.height
        var random = SeededRandom(seed)
        var front: [CGRect] = []
        var x: CGFloat = 0
        while x < w {
            let bw = 8 + random.next() * 18
            let bh = h * (0.18 + random.next() * 0.42)
            front.append(CGRect(x: x, y: h - bh, width: bw, height: bh))
            x += 6 + random.next() * 14
        }
        var back: [CGRect] = []
        let backCount = max(12, Int(w / 12))
        for _ in 0..<backCount {
            let bx = random.next() * w
            let bw = 10 + random.next() * 22
            let bh = h * (0.25 + random.next() * 0.35)
            back.append(CGRect(x: bx, y: h - bh, width: bw, height: bh))
        }
        return (front, back)
    }
}

/// Whether the banner is bright or dark behind the time (its bottom-left corner, about 55% of its
/// width and half its height), as shaded for the time of day there: dark digits outlined in white
/// go on a bright corner, white digits outlined in black on a dark one.
enum BannerInk {
    /// Brighter than this (relative luminance, 0 to 1) takes dark digits.
    static let threshold: Double = 0.40

    /// Recent answers, by photo (or drawn city and size) and phase, so scrubbing stays fast.
    private static var cache: [String: Bool] = [:]

    static func isBright(place: Place, phase: Sky.Phase, size: CGSize) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        let photoKey = SkylineArt.key(for: place.name)
        let key: String
        if let photoKey {
            // A photo's crop depends only on the banner's shape; a step of a quarter is close enough.
            let aspect = (size.width / size.height * 4).rounded() / 4
            key = "photo|\(photoKey)|\(phase)|\(aspect)"
        } else {
            key = "drawn|\(place.name)|\(phase)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }
        if let hit = cache[key] { return hit }
        if cache.count > 200 { cache.removeAll() }

        let luminance: Double?
        if photoKey != nil, let photo = SkylineArt.photo(for: place.name) {
            luminance = photoLuminance(photo, phase: phase, size: size)
        } else {
            luminance = drawnLuminance(seed: place.name, phase: phase, size: size)
        }
        let bright = (luminance ?? 0) > threshold
        cache[key] = bright
        return bright
    }

    // MARK: Colour

    /// sRGB (0...1) to linear light.
    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance of an sRGB colour (0...1 components).
    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    // MARK: Photos

    /// The photo's corner behind the time, as the banner crops it (filling it, centred), drawn into a
    /// small bitmap, then saturated and tinted as the banner shades it, and averaged.
    private static func photoLuminance(_ photo: UIImage, phase: Sky.Phase, size: CGSize) -> Double? {
        guard let cg = photo.cgImage else { return nil }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        guard iw > 0, ih > 0 else { return nil }
        let aspect = size.width / size.height
        var visible = CGRect(x: 0, y: 0, width: iw, height: ih)
        if iw / ih > aspect {
            let vw = ih * aspect
            visible = CGRect(x: (iw - vw) / 2, y: 0, width: vw, height: ih)
        } else {
            let vh = iw / aspect
            visible = CGRect(x: 0, y: (ih - vh) / 2, width: iw, height: vh)
        }
        // Bottom-left: 55% of the width, the lower half (image rows run top to bottom).
        let region = CGRect(x: visible.minX, y: visible.minY + visible.height * 0.5,
                            width: visible.width * 0.55, height: visible.height * 0.5).integral
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard !region.isEmpty, let crop = cg.cropping(to: region) else { return nil }

        let w = 24, h = 12
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        let saturation = SkylineArt.saturation(phase)
        let tint = components(SkylineArt.shade(phase))
        var total = 0.0
        for i in 0..<(w * h) {
            let a = Double(px[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            var r = Double(px[i * 4]) / 255 / a
            var g = Double(px[i * 4 + 1]) / 255 / a
            var b = Double(px[i * 4 + 2]) / 255 / a
            // .saturation: towards (or away from) the pixel's grey.
            let grey = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = min(max(grey + (r - grey) * saturation, 0), 1)
            g = min(max(grey + (g - grey) * saturation, 0), 1)
            b = min(max(grey + (b - grey) * saturation, 0), 1)
            // .colorMultiply: the time of day's tint.
            total += luminance(r * tint.r, g * tint.g, b * tint.b)
        }
        return total / Double(w * h)
    }

    // MARK: Drawn skylines

    /// The drawn skyline's corner behind the time, sampled on a small grid: its buildings in their
    /// ink, the paler row behind at 55% over the sky, and the sky's gradient elsewhere.
    private static func drawnLuminance(seed: String, phase: Sky.Phase, size: CGSize) -> Double {
        let layout = DrawnSkyline.layout(seed: seed, size: size)
        let sky = SkylineArt.sky(phase).map { components($0) }
        let ink = components(SkylineArt.ink(phase))
        let top = sky.first ?? (r: 0, g: 0, b: 0, a: 1)
        let bottom = sky.last ?? top
        let cols = 24, rows = 12
        var total = 0.0
        for row in 0..<rows {
            let t = 0.5 + 0.5 * (Double(row) + 0.5) / Double(rows)
            let y = size.height * CGFloat(t)
            let sr = top.r + (bottom.r - top.r) * t
            let sg = top.g + (bottom.g - top.g) * t
            let sb = top.b + (bottom.b - top.b) * t
            for col in 0..<cols {
                let x = size.width * 0.55 * CGFloat((Double(col) + 0.5) / Double(cols))
                let p = CGPoint(x: x, y: y)
                if layout.front.contains(where: { $0.contains(p) }) {
                    total += luminance(ink.r, ink.g, ink.b)
                } else if layout.back.contains(where: { $0.contains(p) }) {
                    total += luminance(sr + (ink.r - sr) * 0.55, sg + (ink.g - sg) * 0.55, sb + (ink.b - sb) * 0.55)
                } else {
                    total += luminance(sr, sg, sb)
                }
            }
        }
        return total / Double(cols * rows)
    }
}

/// A soft gradient in the banner's bottom-left corner, under the time, so it reads on any sky:
/// dark under white digits, light under dark ones.
struct BannerScrim: View {
    var bright = false

    var body: some View {
        let tone = bright ? Color.white : Color.black
        let corner: Double = bright ? 0.45 : 0.55
        let middle: Double = bright ? 0.2 : 0.25
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: tone.opacity(corner), location: 0),
                Gradient.Stop(color: tone.opacity(middle), location: 0.375),
                Gradient.Stop(color: tone.opacity(0), location: 0.625),
            ],
            center: .bottomLeading,
            startRadiusFraction: 0,
            endRadiusFraction: 1.2
        )
        .animation(.easeInOut(duration: 0.6), value: bright)
        .allowsHitTesting(false)
    }
}

/// The city's time on its banner: semibold digits with AM or PM small after them, on the scrim,
/// with a thin outline and a soft shadow. White outlined in black on a dark corner; on a bright
/// one, near-black outlined in white with a soft white glow.
struct BannerClock: View {
    let moment: Date
    let zone: TimeZone
    let use24h: Bool
    let size: CGFloat
    var bright = false

    /// The eight directions the outline's copies sit in, around the fill.
    private static let directions: [CGSize] = {
        let d = CGFloat(0.5.squareRoot())
        return [CGSize(width: -1, height: 0), CGSize(width: 1, height: 0),
                CGSize(width: 0, height: -1), CGSize(width: 0, height: 1),
                CGSize(width: -d, height: -d), CGSize(width: d, height: -d),
                CGSize(width: -d, height: d), CGSize(width: d, height: d)]
    }()

    private var fillColor: Color { bright ? Theme.rgb(0x141210) : .white }

    var body: some View {
        let parts = clockParts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // The digits' outline is 1 pt at 24 pt, 1.5 pt at 36 pt; AM/PM's is scaled to its own size.
            outlined(digitsText(parts.digits), width: size / 24)
            if let suffix = parts.suffix {
                outlined(suffixText(suffix), width: size * 0.45 / 24)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.numericText())
        .compositingGroup()
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.45 : 0.35), radius: 4, x: 0, y: 0)
        .shadow(color: (bright ? Color.white : Color.black).opacity(bright ? 0.3 : 0.25), radius: 1, x: 0, y: bright ? 0 : 1)
        .animation(.easeInOut(duration: 0.6), value: bright)
    }

    /// The text with an outline under its fill: copies nudged out on every side, drawn opaque
    /// and flattened, so the outline's opacity is applied once rather than stacking up.
    private func outlined(_ t: Text, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<Self.directions.count, id: \.self) { i in
                    t.offset(x: Self.directions[i].width * width, y: Self.directions[i].height * width)
                }
            }
            .foregroundStyle(bright ? Color.white : Color.black)
            .compositingGroup()
            .opacity(bright ? 0.85 : 0.6)
            .accessibilityHidden(true)
            t.foregroundStyle(fillColor)
        }
    }

    private var clockParts: (digits: String, suffix: String?) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let p = cal.dateComponents([.hour, .minute], from: moment)
        return ClockText.parts(hour: p.hour ?? 0, minute: p.minute ?? 0, use24h: use24h)
    }

    private func digitsText(_ digits: String) -> Text {
        Text(digits)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .tracking(-0.02 * size)
    }

    private func suffixText(_ suffix: String) -> Text {
        Text("\u{2009}" + suffix).font(.system(size: size * 0.45, weight: .medium))
    }
}

/// Where a city is in its working week at a moment: working (until when), or off hours, the
/// weekend, a day off or a public holiday (and when work starts again).
struct WorkStatus {
    enum Kind { case working, offHours, weekend, dayOff, holiday }

    let kind: Kind
    /// "Working", "Off hours", "Weekend", "Day off", or the holiday's name.
    let title: String
    /// "until 6 PM", "back 9 AM Mon"; nil when not asked for or not found within 8 days.
    let detail: String?

    var color: Color {
        switch kind {
        case .working: return Theme.rgb(0x9FE3A6)
        case .offHours: return Theme.rgb(0xB9B2A8)
        case .weekend, .dayOff: return Theme.rgb(0xF4C47A)
        case .holiday: return Theme.rgb(0xF29BB5)
        }
    }

    var symbol: String {
        switch kind {
        case .working: return "briefcase.fill"
        case .offHours: return "moon.fill"
        case .weekend: return "sun.max.fill"
        case .dayOff: return "calendar"
        case .holiday: return "star.fill"
        }
    }

    /// "Working, until 6 PM", for VoiceOver.
    var spoken: String { [title, detail].compactMap { $0 }.joined(separator: ", ") }

    static func of(_ place: Place, at moment: Date, start: Int, end: Int, use24h: Bool, withDetail: Bool) -> WorkStatus {
        let working = WorkWeek.isWorking(place, at: moment, start: start, end: end)
        let kind: Kind
        let title: String
        if working {
            kind = .working; title = "Working"
        } else {
            let off = WorkWeek.offLabel(place, at: moment, start: start, end: end) ?? "Off hours"
            switch off {
            case "Off hours": kind = .offHours
            case "Weekend": kind = .weekend
            case "Day off": kind = .dayOff
            default: kind = .holiday
            }
            title = off
        }
        guard withDetail, let change = nextChange(place, from: moment, working: working, start: start, end: end) else {
            return WorkStatus(kind: kind, title: title, detail: nil)
        }
        let cal = place.calendar
        let parts = cal.dateComponents([.hour, .minute], from: change)
        var text = WorkWeek.clock(Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60, use24h: use24h)
        if !cal.isDate(change, inSameDayAs: moment) { text += " " + TimeMath.weekday(change, in: place.timeZone) }
        return WorkStatus(kind: kind, title: title, detail: (working ? "until " : "back ") + text)
    }

    /// Recent answers, so scrubbing and redrawing don't scan the week again.
    private static var cache: [String: Date?] = [:]

    /// The first quarter-hour after the moment when the city stops (or starts) working, looking up
    /// to 8 days ahead: hour by hour, then quarter-hour by quarter-hour within the hour it changes.
    static func nextChange(_ place: Place, from moment: Date, working: Bool, start: Int, end: Int) -> Date? {
        let base = Date(timeIntervalSinceReferenceDate: (moment.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
        let days = place.workDays.map { $0.sorted().map(String.init).joined(separator: ",") } ?? "-"
        let key = [place.timeZoneID, place.countryCode ?? "", days, "\(place.workStart ?? -1)", "\(place.workEnd ?? -1)",
                   "\(start)", "\(end)", "\(Holidays.counted)", "\(working)", "\(base.timeIntervalSinceReferenceDate)"]
            .joined(separator: "|")
        if let hit = cache[key] { return hit }
        if cache.count > 400 { cache.removeAll() }

        func flips(_ t: Date) -> Bool { WorkWeek.isWorking(place, at: t, start: start, end: end) != working }
        var result: Date?
        var previous = base
        for h in 1...(8 * 24) {
            let t = base.addingTimeInterval(Double(h) * 3600)
            if flips(t) {
                result = t
                for q in 1...3 {
                    let u = previous.addingTimeInterval(Double(q) * 900)
                    if flips(u) { result = u; break }
                }
                break
            }
            previous = t
        }
        cache[key] = result
        return result
    }
}

/// A city's working status as a small outlined capsule: an icon and the status in its colour, with
/// the detail after a dot in tall cards.
struct StatusPill: View {
    let status: WorkStatus
    var showDetail = false
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
                .font(.system(size: 9 * scale, weight: .semibold))
            label
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(status.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spoken)
    }

    private var label: Text {
        let title = Text(status.title).font(.system(size: 11.5 * scale, weight: .semibold))
        guard showDetail, let detail = status.detail else { return title }
        return title + Text(" \u{00B7} " + detail).font(.system(size: 11.5 * scale, weight: .medium)).foregroundStyle(status.color.opacity(0.85))
    }
}

/// Settings → About → Photo Credits: where the skyline photos come from.
struct PhotoCreditsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(SkylineArt.credits, id: \.city) { credit in
                    Link(destination: credit.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.city).foregroundStyle(.white)
                            Text(credit.file)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(Theme.Op.caption))
                        }
                    }
                }
            } footer: {
                Text("Skyline photos from Wikimedia Commons. Tap one to see its author and licence there. Other cities show a skyline drawn by Meridian.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(Theme.Op.caption))
            }
            .meridianSection()
        }
        .meridianForm()
        .navigationTitle("Photo Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
