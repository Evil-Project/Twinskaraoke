import Testing
@testable import Twinskaraoke

struct PlayerTimecodeTests {
    @Test func playbackShowsElapsedAndCountsDownTheRest() {
        let labels = PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: 0.36, isScrubbing: false)
        #expect(labels == PlayerTimecode.Labels(elapsed: "1:05", remaining: "-1:55"))
    }

    /// Under a scrubbing finger both labels show where it is, not where
    /// playback still is.
    @Test func scrubbingMovesBothLabelsWithTheFinger() {
        let labels = PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: 0.5, isScrubbing: true)
        #expect(labels == PlayerTimecode.Labels(elapsed: "1:30", remaining: "-1:30"))
        #expect(PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: 1.4, isScrubbing: true).elapsed == "3:00")
        #expect(PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: -1, isScrubbing: true).elapsed == "0:00")
    }

    /// The clock is passed on every pass so the labels keep ticking; outside
    /// a scrub it must not move them off the playback position.
    @Test func theClockOnlyMovesTheLabelsWhileScrubbing() {
        let playing = PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: 0.9, isScrubbing: false)
        #expect(playing.elapsed == "1:05")
        // Closed player: no clock, even if a scrub flag is left set.
        let closed = PlayerTimecode.labels(elapsed: 65, duration: 180, clockProgress: nil, isScrubbing: true)
        #expect(closed.elapsed == "1:05")
    }

    @Test func anUnknownLengthShowsZeroWithoutAMinus() {
        let labels = PlayerTimecode.labels(elapsed: 12, duration: 0, clockProgress: nil, isScrubbing: false)
        #expect(labels == PlayerTimecode.Labels(elapsed: "0:00", remaining: "0:00"))
        #expect(PlayerTimecode.string(.nan) == "0:00")
        #expect(PlayerTimecode.string(3_725) == "62:05")
    }
}
