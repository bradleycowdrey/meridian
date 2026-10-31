import SwiftUI

/// Terms of Use and Privacy: asked once, and again when they change, at most once a month (see
/// TermsVersion; the built-in version matches the Mac app's).
enum Terms {
    static let version = "2026-10-31"
    /// Agreed, and nothing newer is waiting to be asked.
    static var accepted: Bool { !TermsVersion.due(builtIn: version) }
    /// Agreed to an earlier version (so this is an update).
    static var changed: Bool { TermsVersion.agreed != nil }
    static func accept() { TermsVersion.accept(builtIn: version) }
}

struct TermsView: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Mark")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(Terms.changed ? "The Terms of Use and Privacy have changed" : "Terms of Use and Privacy")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.primary)
            Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your iPhone. If you allow it, your location is used only to name the city you're in.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onAgree) {
                Text("I Agree").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cream)
            .foregroundStyle(Theme.bg)
            Link("Read the Terms", destination: Theme.legal)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cream)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}
