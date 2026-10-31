import AppKit

/// Terms of Use and Privacy: asked once, and again when they change (at most once a month; see
/// TermsVersion). Never asked during the CI self-test, so the test can drive the app unattended.
enum Terms {
    /// Agreed, and nothing newer is waiting to be asked.
    static var accepted: Bool { !TermsVersion.due(builtIn: Brand.termsVersion) }

    /// At launch and every few hours (the app runs for weeks): look for changed terms, and ask.
    @MainActor
    static func startChecking() {
        Task { @MainActor in
            // Let the app finish launching first.
            try? await Task.sleep(for: .milliseconds(500))
            await TermsVersion.refresh()
            askIfNeeded()
        }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in
                await TermsVersion.refresh()
                askIfNeeded()
            }
        }
    }

    @MainActor
    static func askIfNeeded() {
        guard !accepted, !SelfTest.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = TermsVersion.agreed == nil ? "Terms of Use and Privacy" : "The Terms of Use and Privacy have changed"
        alert.informativeText = "Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your Mac. If you allow it, your location is used only to name the city you're in.\n\nBy choosing I Agree and using \(Brand.appName), you agree to the Terms of Use and Privacy at bradcowdrey.com/legal."
        alert.addButton(withTitle: "I Agree")
        alert.addButton(withTitle: "Read the Terms")
        alert.addButton(withTitle: "Quit")
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                TermsVersion.accept(builtIn: Brand.termsVersion)
                return
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(Brand.legal)
            default:
                NSApp.terminate(nil)
                return
            }
        }
    }
}
