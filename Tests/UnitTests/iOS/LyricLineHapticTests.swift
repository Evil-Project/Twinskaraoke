import Testing
@testable import Twinskaraoke

/// Lyric lines sit in a scroll view. A style haptic fires on touch-down, so a
/// drag that starts on a line ticked although nothing was picked; the tick
/// belongs to the seek, as in `SongRow`.
@MainActor
struct LyricLineHapticTests {
    @Test func aLyricLineTicksOnTheSeekNotOnTouchDown() {
        #expect(LyricLineRow.pressHaptic == nil)
    }
}
