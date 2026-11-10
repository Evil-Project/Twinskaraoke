import SwiftUI

/// Takes the app shell out of the accessibility tree while the full-screen
/// player covers it.
///
/// The player is an overlay in the same window, not a modal presentation, so
/// nothing told VoiceOver that the screens underneath were out of reach: a
/// swipe past the player's last control moved on to Home, the tab bar and the
/// mini player, all of them behind the player.
///
/// Keyed on `isExpanded`, the committed state. A dismissal drag that is still
/// in flight leaves the player open, and the shell should not come and go
/// under a finger that has not decided yet.
///
/// Only while there is a player to hide behind. The presentation can be
/// expanded with no song loaded (the Now Playing widget opens the player
/// either way), and the overlay draws nothing then: hiding the shell too
/// would leave VoiceOver with nothing on screen to focus.
///
/// A modifier of its own, so that only this body reads the presentation. Read
/// from the root view instead, every open and close would rebuild the shell.
private struct HiddenBehindPlayer: ViewModifier {
    let presentation: NowPlayingPresentation
    private let snapshot = NowPlayingSnapshotState.shared

    func body(content: Content) -> some View {
        content.accessibilityHidden(
            PlayerAccessibilityGate.hidesShell(
                isExpanded: presentation.isExpanded,
                hasCurrentSong: snapshot.hasCurrentSong
            )
        )
    }
}

enum PlayerAccessibilityGate {
    static func hidesShell(isExpanded: Bool, hasCurrentSong: Bool) -> Bool {
        isExpanded && hasCurrentSong
    }
}

extension View {
    func accessibilityHiddenBehindPlayer(
        _ presentation: NowPlayingPresentation = .shared
    ) -> some View {
        modifier(HiddenBehindPlayer(presentation: presentation))
    }
}
