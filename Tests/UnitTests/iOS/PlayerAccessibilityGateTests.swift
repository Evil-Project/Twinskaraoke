import Testing
@testable import Twinskaraoke

struct PlayerAccessibilityGateTests {
    @Test func theShellIsHiddenBehindAnOpenPlayer() {
        #expect(PlayerAccessibilityGate.hidesShell(isExpanded: true, hasCurrentSong: true))
        #expect(!PlayerAccessibilityGate.hidesShell(isExpanded: false, hasCurrentSong: true))
    }

    /// The Now Playing widget expands the presentation even with nothing
    /// loaded. The overlay draws no player then, so the shell is all there is.
    @Test func theShellStaysReachableWhenThereIsNoPlayerToShow() {
        #expect(!PlayerAccessibilityGate.hidesShell(isExpanded: true, hasCurrentSong: false))
        #expect(!PlayerAccessibilityGate.hidesShell(isExpanded: false, hasCurrentSong: false))
    }
}
