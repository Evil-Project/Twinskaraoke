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
    /// - Parameter scrubProgress: where the finger is, from 0 to 1, or nil
    ///   when nobody is scrubbing.
    static func labels(elapsed: Double, duration: Double, scrubProgress: Double?) -> Labels {
        let length = max(duration, 0)
        let position: Double = if let scrubProgress {
            length * min(1, max(0, scrubProgress))
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
