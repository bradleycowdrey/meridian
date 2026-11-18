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
    #if APPSTORE
    /// Mac App Store build: Share points to the App Store (one app for iPhone and Mac), and names
    /// no other platform or download (App Review 2.3.10).
    static let shareMessage = "Meridian: every time zone at a glance, for iPhone and Mac. In your Mac's menu bar and on your desktop. Free, by Bradley Cowdrey."
    static let productPage = URL(string: "https://apps.apple.com/app/id6826713540")!
    #else
    /// What Share says, as Two Degrees does: the app, what it does here, who made it.
    static let shareMessage = "Meridian: every time zone at a glance, in your Mac's menu bar and on your desktop. Free and open source, by Bradley Cowdrey."
    static let productPage = URL(string: "https://bradcowdrey.com/meridian")!
    /// The self-updater's release feed (not in the Mac App Store build, which has no updater).
    static let releasesAPI = URL(string: "https://api.github.com/repos/bradleycowdrey/meridian/releases/latest")!
    #endif
    static let issues = URL(string: "https://github.com/bradleycowdrey/meridian/issues")!
    static let copyright = "© 2026 Bradley Cowdrey · bradcowdrey.com"
}
