import Testing
@testable import Twinskaraoke

/// One touch, one haptic: a button either plays it from its action or from
/// its style, never both.
@MainActor
struct NewFeatureCardHapticTests {
    @Test func aCardThatPlaysLeavesTheHapticToItsAction() {
        // The Trending Now card's action plays `.selection` itself.
        #expect(NewFeatureCard.Action.play {}.styleHaptic == nil)
    }

    @Test func aCardThatOpensAPlaylistTicksOnTouchDown() {
        let playlist = Playlist(id: "a", name: "A", songCount: 0, mosaicMedia: nil, songListDTOs: nil)
        #expect(NewFeatureCard.Action.open(playlist, play: {}).styleHaptic == .selection)
    }
}
