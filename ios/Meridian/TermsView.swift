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

    /// As Two Degrees' terms screen: the mark, a large title, the summary, and a white I Agree.
    var body: some View {
        // Scrolls only when the reader's text size makes it taller than the screen (nothing is cut off).
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.bg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Mark")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(Terms.changed ? "The Terms of Use and Privacy have changed" : "Terms of Use and Privacy")
                .font(.title.weight(.semibold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your iPhone. If you allow it, your location is used only to name the city you're\u{00A0}in.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onAgree) {
                Text("I Agree")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Color.black)
                    .background(Capsule().fill(Theme.cream))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Link(destination: Theme.legal) {
                Text("Read the Terms")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
    }
}
