import SwiftUI

/// Terms of Use and Privacy: asked once, and again if the terms change (same version as the Mac app).
enum Terms {
    static let version = "2026-10-21"
    private static let key = "terms.accepted"
    static var accepted: Bool { UserDefaults.standard.string(forKey: key) == version }
    static func accept() { UserDefaults.standard.set(version, forKey: key) }
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
            Text("Terms of Use and Privacy")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primary)
            Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your iPhone.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.")
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
