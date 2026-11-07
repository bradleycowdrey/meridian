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

        var random = SeededRandom(seed)
        // Windows draw from their own generator so the buildings never change with the phase.
        var lights = SeededRandom(seed + "|windows")
        let ink = SkylineArt.ink(phase)
        let windowChance: CGFloat = phase == .night ? 0.35 : (phase == .twilight ? 0.18 : 0)

        // The front row of buildings, and their lit windows.
        var front = Path()
        var windows = Path()
        var x: CGFloat = 0
        while x < w {
            let bw = 8 + random.next() * 18
            let bh = h * (0.18 + random.next() * 0.42)
            front.addRect(CGRect(x: x, y: h - bh, width: bw, height: bh))
            if windowChance > 0 {
                var y = h - bh + 4
                while y < h - 3 {
                    var wx = x + 2
                    while wx < x + bw - 2 {
                        if lights.next() < windowChance { windows.addRect(CGRect(x: wx, y: y, width: 1.6, height: 2)) }
                        wx += 4
                    }
                    y += 5
                }
            }
            x += 6 + random.next() * 14
        }

        // A paler row behind.
        var back = Path()
        let backCount = max(12, Int(w / 12))
        for _ in 0..<backCount {
            let bx = random.next() * w
            let bw = 10 + random.next() * 22
            let bh = h * (0.25 + random.next() * 0.35)
            back.addRect(CGRect(x: bx, y: h - bh, width: bw, height: bh))
        }

        context.fill(back, with: .color(ink.opacity(0.55)))
        context.fill(front, with: .color(ink))
        context.fill(windows, with: .color(Theme.rgb(0xFFD98A).opacity(0.8)))
    }
}

/// A soft dark gradient in the banner's bottom-left corner, under the time, so the white digits
/// read on bright skies as well as night ones.
struct BannerScrim: View {
    var body: some View {
        EllipticalGradient(
            stops: [
                .init(color: Color.black.opacity(0.55), location: 0),
                .init(color: Color.black.opacity(0.25), location: 0.375),
                .init(color: Color.black.opacity(0), location: 0.625),
            ],
            center: .bottomLeading,
            startRadiusFraction: 0,
            endRadiusFraction: 1.2
        )
        .allowsHitTesting(false)
    }
}

/// The city's time on its banner: white semibold digits with AM or PM small after them, on the
/// scrim, with a soft shadow.
struct BannerClock: View {
    let moment: Date
    let zone: TimeZone
    let use24h: Bool
    let size: CGFloat

    var body: some View {
        clock
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
    }

    private var clock: Text {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let p = cal.dateComponents([.hour, .minute], from: moment)
        let parts = ClockText.parts(hour: p.hour ?? 0, minute: p.minute ?? 0, use24h: use24h)
        let digits = Text(parts.digits)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .tracking(-0.02 * size)
        guard let suffix = parts.suffix else { return digits }
        let small = Text("\u{2009}" + suffix).font(.system(size: size * 0.45, weight: .medium))
        return digits + small
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
