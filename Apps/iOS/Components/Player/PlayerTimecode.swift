import Foundation

/// The two timecodes under the player's scrubber.
nonisolated enum PlayerTimecode {
    struct Labels: Equatable {
        let elapsed: String
        let remaining: String
    }

    /// While a finger is on the scrubber, both labels follow it, as Apple
    /// Music's do: they say where letting go would land, not where playback
    /// still is. The remaining time counts down, so it carries a minus.
    ///
    /// - Parameters:
    ///   - clockProgress: the playback clock, from 0 to 1, which the scrubber
    ///     writes while a finger is on it; nil while the player is closed.
    ///     The caller reads it on every pass, scrubbing or not: that read is
    ///     what redraws the labels as playback ticks. Taking it only while
    ///     scrubbing would freeze them.
    ///   - isScrubbing: whether a finger is on the scrubber.
    static func labels(
        elapsed: Double,
        duration: Double,
        clockProgress: Double?,
        isScrubbing: Bool
    ) -> Labels {
        let length = max(duration, 0)
        let position: Double = if isScrubbing, let clockProgress {
            length * min(1, max(0, clockProgress))
        } else {
            min(max(elapsed, 0), length)
        }
        let remaining = string(max(0, length - position))
        return Labels(elapsed: string(position), remaining: length > 0 ? "-\(remaining)" : remaining)
    }

    static func string(_ seconds: Double) -> String {
        let whole = Int(seconds.isFinite ? max(0, seconds) : 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
