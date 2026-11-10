import SwiftUI

/// An empty state for something that needs an account, with the way there.
///
/// The message used to be all there was: "Sign in from Account…", and then
/// finding Account was left to the reader.
struct SignInRequiredState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AM.Spacing.l) {
            MusicEmptyState(title: title, message: message)
            SignInEmptyStateLink()
        }
    }
}

/// Opens Account, where signing in lives. A link to the existing screen, so
/// signing in, and everything that follows it, stays in one place.
struct SignInEmptyStateLink: View {
    var body: some View {
        NavigationLink {
            DeferredView { AccountView() }
        } label: {
            MusicEmptyActionLabel(title: String(localized: "Sign In"))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
        .accessibilityHint("Opens account and settings.")
        .accessibilityIdentifier("EmptyState.SignIn")
    }
}
