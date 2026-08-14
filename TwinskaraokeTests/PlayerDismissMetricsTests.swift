import CoreGraphics
import Testing
@testable import Twinskaraoke

/// Guards the drag-to-dismiss decision for the full-screen player.
///
/// These are regression tests in the literal sense: the app previously used
/// LNPopupController, whose snap style decided dismissal from absolute position
/// alone and discarded velocity when the finger lifted, so roughly one downward
/// flick in three was rejected and sprang back. `flickDismissesDespiteShortTravel`
/// is that exact case.
@Suite("Player dismissal metrics")
struct PlayerDismissMetricsTests {
    /// A full-screen player on a modern phone. The thresholds are fractions of
    /// this, so the numbers below read as real gestures rather than ratios:
    /// the projection must reach 225pt to commit.
    private let height: CGFloat = 900

    // MARK: - Committing

    /// The whole point. A flick travels barely an eighth of the screen before
    /// the finger leaves it, but it is moving fast enough that the system
    /// projects it well past the threshold.
    ///
    /// The projected value is what a hard downward flick actually produces:
    /// `predictedEndTranslation` is roughly a quarter-second of continued
    /// travel, so ~2400pt/s carries this from 120pt to about 700pt.
    @Test("A fast flick dismisses even though it barely moved")
    func flickDismissesDespiteShortTravel() {
        #expect(PlayerDismissMetrics.shouldDismiss(
            translation: 120, predictedTranslation: 700, height: height
        ))
    }

    /// The other way to commit: no throw at all, just pulled far enough that
    /// where it stopped is already past the mark.
    @Test("A slow drag past the threshold dismisses on distance alone")
    func slowDragPastThresholdDismisses() {
        #expect(PlayerDismissMetrics.shouldDismiss(
            translation: 300, predictedTranslation: 300, height: height
        ))
    }

    // MARK: - Springing back

    @Test("A short drag released at rest springs back")
    func shortDragAtRestDoesNotDismiss() {
        #expect(!PlayerDismissMetrics.shouldDismiss(
            translation: 120, predictedTranslation: 130, height: height
        ))
    }

    /// A reversal is a cancellation, however far the drag got first. This is
    /// why the predicate has no "…or it travelled far enough" clause: pulled
    /// two thirds of the way down and then flicked back up, the projection
    /// lands above the threshold and the player stays.
    @Test("Flicking back up cancels a drag that had already gone far")
    func upwardReversalCancels() {
        #expect(!PlayerDismissMetrics.shouldDismiss(
            translation: 600, predictedTranslation: 100, height: height
        ))
    }

    @Test("An upward drag never dismisses")
    func upwardDragNeverDismisses() {
        #expect(!PlayerDismissMetrics.shouldDismiss(
            translation: -200, predictedTranslation: -600, height: height
        ))
    }

    /// Before the first layout pass there is no height to measure against.
    /// Committing on a zero-height player would dismiss it out from under a
    /// gesture that had not started.
    @Test("A zero height never dismisses")
    func zeroHeightNeverDismisses() {
        #expect(!PlayerDismissMetrics.shouldDismiss(
            translation: 500, predictedTranslation: 900, height: 0
        ))
    }

    // MARK: - Rubberband

    /// `(x·d·c) / (d + c·x)` tends to `d` as `x` grows — dividing through by
    /// `x` leaves `(d·c) / (d/x + c)`, and the `d/x` term vanishes. So the
    /// player can never be pulled further than its own height upward, however
    /// hard someone drags.
    @Test("Rubberband resists rather than blocks, and never reaches its asymptote")
    func rubberbandIsBoundedAndMonotonic() {
        let ceiling = height
        var previous: CGFloat = 0
        for distance in stride(from: CGFloat(10), through: 4000, by: 10) {
            let resisted = PlayerDismissMetrics.rubberband(distance, limit: height)
            #expect(resisted > previous, "expected monotonic growth at \(distance)")
            #expect(resisted < distance, "expected resistance at \(distance)")
            #expect(resisted < ceiling, "expected to stay under \(ceiling) at \(distance)")
            previous = resisted
        }
    }

    @Test("Rubberband passes through zero and mirrors")
    func rubberbandMirrors() {
        #expect(PlayerDismissMetrics.rubberband(0, limit: height) == 0)
        #expect(
            PlayerDismissMetrics.rubberband(-250, limit: height)
                == -PlayerDismissMetrics.rubberband(250, limit: height)
        )
    }

    @Test("A zero limit has nothing to resist against")
    func rubberbandWithoutLimit() {
        #expect(PlayerDismissMetrics.rubberband(250, limit: 0) == 0)
    }

    // MARK: - Offset and progress

    /// Downward travel has to track the finger exactly. Resisting it is what
    /// made earlier attempts at this feel indirect.
    @Test("Downward drag tracks the finger one-to-one")
    func downwardOffsetIsUnresisted() {
        #expect(PlayerDismissMetrics.dragOffset(forTranslation: 240, height: height) == 240)
    }

    @Test("Upward drag is resisted, since there is nothing above the player")
    func upwardOffsetIsRubberbanded() {
        let offset = PlayerDismissMetrics.dragOffset(forTranslation: -240, height: height)
        #expect(offset < 0)
        #expect(offset > -240)
    }

    @Test("Progress spans the player's height and clamps at both ends")
    func progressClamps() {
        #expect(PlayerDismissMetrics.progress(forOffset: 0, height: height) == 1)
        #expect(PlayerDismissMetrics.progress(forOffset: height, height: height) == 0)
        #expect(PlayerDismissMetrics.progress(forOffset: height * 2, height: height) == 0)
        #expect(PlayerDismissMetrics.progress(forOffset: -100, height: height) == 1)
        #expect(abs(PlayerDismissMetrics.progress(forOffset: 450, height: height) - 0.5) < 0.0001)
    }
}
