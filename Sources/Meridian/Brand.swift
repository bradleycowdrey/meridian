import Foundation

/// Single source of truth for branding. Change these to rebrand the app.
enum Brand {
    static let appName = "Meridian"
    static let tagline = "Every time zone at a glance."
    static let author = "Bradley Cowdrey"
    static let websiteHost = "bradcowdrey.com"
    static let website = URL(string: "https://bradcowdrey.com")!
    static let legal = URL(string: "https://bradcowdrey.com/legal")!
    /// Bump when the terms change materially, so everyone is asked to agree again.
    static let termsVersion = "2026-10-31"
    static let repository = URL(string: "https://github.com/bradleycowdrey/meridian")!
    static let shareMessage = "Meridian: every time zone at a glance, in your Mac's menu bar. Free and open source, by Bradley Cowdrey."
    static let releasesAPI = URL(string: "https://api.github.com/repos/bradleycowdrey/meridian/releases/latest")!
    static let issues = URL(string: "https://github.com/bradleycowdrey/meridian/issues")!
    static let copyright = "© 2026 Bradley Cowdrey · bradcowdrey.com"
}
