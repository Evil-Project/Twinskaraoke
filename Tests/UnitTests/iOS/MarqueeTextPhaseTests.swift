import CoreGraphics
import Foundation
import Testing
@testable import Twinskaraoke

/// Guards the scrolling title in the radio player.
///
/// These are regression tests. `MarqueeText` used to drive its offset with an
/// implicit animation and step the loop with `Task.sleep`, which assumed the
/// wall clock and the animation stayed in step. Opening or dismissing the
/// full-screen player runs a `withAnimation` transaction over the player's whole
/// subtree, which could drop the in-flight animation while the sleep carried on
/// — the title stalled mid-pass, then jumped. Making the offset a total function
/// of elapsed time is the fix, so what is worth testing is that it really is
/// total: same input, same output, no matter what happened in between.
@Suite("Marquee scrolling")
struct MarqueeTextPhaseTests {
    /// A title about twice the width of the space it has, at the default gap.
    private let travel: CGFloat = 400
    private let scrollDuration: TimeInterval = 400 / 35
    private let startDelay: TimeInterval = 1.2

    private func phase(_ elapsed: TimeInterval) -> CGFloat {
        MarqueeText.phase(
            elapsed: elapsed,
            travel: travel,
            scrollDuration: scrollDuration,
            startDelay: startDelay
        )
    }

    // MARK: - One cycle

    @Test("The title holds still for the opening dwell")
    func dwellsBeforeScrolling() {
        #expect(phase(0) == 0)
        #expect(phase(startDelay - 0.01) == 0)
        #expect(phase(startDelay) == 0)
    }

    @Test("A pass runs from the start of the text to the second copy")
    func scrollsAcrossOneFullTravel() {
        #expect(phase(startDelay + 0.001) > 0)
        #expect(phase(startDelay + scrollDuration / 2).isApproximatelyEqual(to: travel / 2))
        // The end of a pass is the start of the next cycle's dwell, so it wraps
        // to zero rather than landing on `travel`. Visually they are the same
        // point: the trailing copy is exactly where the leading one began.
        #expect(phase(startDelay + scrollDuration * 0.999).isApproximatelyEqual(to: travel, within: 1))
        #expect(phase(startDelay + scrollDuration) == 0)
    }

    @Test("A pass advances steadily and never goes backwards within itself")
    func advancesMonotonicallyWithinAPass() {
        var previous: CGFloat = 0
        for step in 1 ... 50 {
            let current = phase(startDelay + scrollDuration * Double(step) / 51)
            #expect(current > previous)
            previous = current
        }
    }

    @Test("Cycles repeat identically")
    func repeatsEveryCycle() {
        let cycle = startDelay + scrollDuration
        for offset in stride(from: 0.0, to: cycle, by: cycle / 17) {
            #expect(phase(offset).isApproximatelyEqual(to: phase(offset + cycle * 4)))
        }
    }

    // MARK: - The regression

    /// The property the old implementation did not have. Nothing carries over
    /// between samples, so a gap — a dropped frame, a paused display link, a
    /// player transition that swallowed the animation — cannot leave the title
    /// stranded: the position is whatever the clock says, both across a gap and
    /// after one.
    @Test("A gap in sampling does not shift the title")
    func survivesAGapInSampling() {
        let cycle = startDelay + scrollDuration
        let resumed = startDelay + scrollDuration * 0.75

        // Sampled continuously or not at all since t=0, the answer is the same.
        #expect(phase(resumed).isApproximatelyEqual(to: travel * 0.75))
        // And a gap spanning several whole cycles still lands in the right place.
        #expect(phase(resumed + cycle * 3).isApproximatelyEqual(to: travel * 0.75))
    }

    // MARK: - Degenerate input

    @Test("Text that fits, or a zero-length pass, never moves")
    func staysPutWithNothingToScroll() {
        #expect(
            MarqueeText.phase(
                elapsed: 99, travel: 0, scrollDuration: scrollDuration, startDelay: startDelay
            ) == 0
        )
        #expect(
            MarqueeText.phase(
                elapsed: 99, travel: travel, scrollDuration: 0, startDelay: startDelay
            ) == 0
        )
    }

    @Test("No dwell means the pass starts immediately")
    func honoursAZeroDwell() {
        let immediate = MarqueeText.phase(
            elapsed: scrollDuration / 4, travel: travel, scrollDuration: scrollDuration,
            startDelay: 0
        )
        #expect(immediate.isApproximatelyEqual(to: travel / 4))
    }

    /// `startDate` is only ever set to the present, so a negative elapsed means
    /// the clock moved underneath us. Restarting the cycle beats a negative
    /// offset, which would push the text off to the right.
    @Test("A clock that moves backwards restarts the cycle")
    func clampsNegativeElapsedTime() {
        #expect(phase(-5) == 0)
    }
}

private extension CGFloat {
    func isApproximatelyEqual(to other: CGFloat, within tolerance: CGFloat = 0.001) -> Bool {
        abs(self - other) <= tolerance
    }
}
