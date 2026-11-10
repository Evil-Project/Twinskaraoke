import Testing
@testable import Twinskaraoke

struct PlayerTimecodeTests {
    @Test func playbackShowsElapsedAndCountsDownTheRest() {
        let labels = PlayerTimecode.labels(elapsed: 65, duration: 180, scrubProgress: nil)
        #expect(labels == PlayerTimecode.Labels(elapsed: "1:05", remaining: "-1:55"))
    }

    /// Under a scrubbing finger both labels show where it is, not where
    /// playback still is.
    @Test func scrubbingMovesBothLabelsWithTheFinger() {
        let labels = PlayerTimecode.labels(elapsed: 65, duration: 180, scrubProgress: 0.5)
        #expect(labels == PlayerTimecode.Labels(elapsed: "1:30", remaining: "-1:30"))
        #expect(PlayerTimecode.labels(elapsed: 65, duration: 180, scrubProgress: 1.4).elapsed == "3:00")
        #expect(PlayerTimecode.labels(elapsed: 65, duration: 180, scrubProgress: -1).elapsed == "0:00")
    }

    @Test func anUnknownLengthShowsZeroWithoutAMinus() {
        let labels = PlayerTimecode.labels(elapsed: 12, duration: 0, scrubProgress: nil)
        #expect(labels == PlayerTimecode.Labels(elapsed: "0:00", remaining: "0:00"))
        #expect(PlayerTimecode.string(.nan) == "0:00")
        #expect(PlayerTimecode.string(3_725) == "62:05")
    }
}
