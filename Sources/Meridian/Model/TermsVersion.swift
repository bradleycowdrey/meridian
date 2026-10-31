import Foundation

/// Which version of the Terms of Use and Privacy you agreed to, and when to ask again (Mac and
/// iPhone; Android does the same in Store.kt).
///
/// The latest version is the "Last updated" date of TERMS.md on GitHub (looked up at most once a
/// day), or the version built into the app, whichever is newer, so a change to the terms is asked
/// for without an app update. The first time, you're always asked; after that, a changed version
/// is asked for at most once a month (30 days after you last agreed).
enum TermsVersion {
    static let source = URL(string: "https://raw.githubusercontent.com/bradleycowdrey/cowdrey-md/main/TERMS.md")!
    static let month: TimeInterval = 30 * 86_400

    private static var defaults: UserDefaults { .standard }

    /// The version agreed to, if any.
    static var agreed: String? { defaults.string(forKey: "terms.accepted") }

    static func latest(builtIn: String) -> String {
        max(builtIn, defaults.string(forKey: "terms.latest") ?? "")
    }

    /// Ask now? Always before the first agreement; for a newer version, once a month at most.
    static func due(builtIn: String, now: Date = Date()) -> Bool {
        guard let agreed else { return true }
        guard agreed < latest(builtIn: builtIn) else { return false }
        let agreedAt = defaults.object(forKey: "terms.acceptedAt") as? Date ?? .distantPast
        return now.timeIntervalSince(agreedAt) >= month
    }

    static func accept(builtIn: String) {
        defaults.set(latest(builtIn: builtIn), forKey: "terms.accepted")
        defaults.set(Date(), forKey: "terms.acceptedAt")
    }

    /// Looks up the latest version on GitHub, at most once a day. Offline, nothing changes.
    static func refresh() async {
        if let checked = defaults.object(forKey: "terms.checkedAt") as? Date, Date().timeIntervalSince(checked) < 86_400 { return }
        let request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let version = version(from: String(decoding: data, as: UTF8.self)) else { return }
        defaults.set(version, forKey: "terms.latest")
        defaults.set(Date(), forKey: "terms.checkedAt")
    }

    /// "Last updated: October 31, 2026" -> "2026-10-31".
    static func version(from markdown: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"Last updated: ([A-Z][a-z]+ \d{1,2}, \d{4})"#),
              let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              let range = Range(match.range(at: 1), in: markdown) else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(identifier: "UTC")
        input.dateFormat = "MMMM d, yyyy"
        guard let date = input.date(from: String(markdown[range])) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = TimeZone(identifier: "UTC")
        output.dateFormat = "yyyy-MM-dd"
        return output.string(from: date)
    }
}
