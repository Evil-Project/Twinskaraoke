import CoreGraphics
import Testing
@testable import Twinskaraoke

@MainActor
struct NowPlayingPresentationTests {
    private func stateWithArtwork() -> NowPlayingPresentation {
        let state = NowPlayingPresentation()
        state.reportBarFrame(CGRect(x: 13, y: 691, width: 350, height: 58))
        state.reportBarArtworkFrame(CGRect(x: 25, y: 700, width: 40, height: 40))
        state.reportPlayerArtworkFrame(CGRect(x: 40, y: 150, width: 300, height: 300))
        return state
    }

    @Test func closingDragAndFallbackKeepOriginalArtwork() {
        let state = stateWithArtwork()
        state.expand()
        #expect(state.isMorphingArtwork)
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        for progress in [0.95, 0.75, 0.5, 0.2] {
            state.drag(to: progress, from: .fullPlayer)
            #expect(!state.isMorphingArtwork)
        }
        state.endDrag(dismissing: true, from: .fullPlayer)
        #expect(state.isAnimatingTransition)
        #expect(!state.isMorphingArtwork)
        state.applyAnimationTarget()
        #expect(!state.isMorphingArtwork)
        state.animationDidComplete(token: state.animationToken)
        #expect(!state.isMorphingArtwork)
    }

    @Test func landingStartsOnlyAfterCommitAndCanBeInterruptedByReopening() {
        let state = stateWithArtwork()
        state.expand()
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.drag(to: 0.8, from: .fullPlayer)
        state.prepareClosingSettlement()
        #expect(!state.isSettlingArtwork)
        state.cancelDrag(from: .fullPlayer)
        state.prepareClosingSettlement()
        #expect(!state.isSettlingArtwork)
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.collapse()
        state.prepareClosingSettlement()
        #expect(state.isSettlingArtwork)
        #expect(state.isMorphingArtwork)
        #expect(state.canBeginMiniPlayerContact)
        let closingToken = state.animationToken
        state.applyAnimationTarget()
        state.drag(to: 0.02, from: .miniPlayer)
        #expect(!state.isSettlingArtwork)
        #expect(state.progress == 0.02)
        state.animationDidComplete(token: closingToken)
        #expect(state.dragSource == .miniPlayer)
    }

    @Test func missingDestinationSkipsClosingSettlement() {
        let state = stateWithArtwork()
        state.reportBarFrame(nil)
        state.expand()
        state.collapse()
        state.prepareClosingSettlement()
        #expect(!state.isSettlingArtwork)
    }

    @Test func cancelledClosingKeepsArtworkAttachedAndNextOpeningStillMorphs() {
        let state = stateWithArtwork()
        state.expand()
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.drag(to: 0.8, from: .fullPlayer)
        state.cancelDrag(from: .fullPlayer)
        #expect(!state.isMorphingArtwork)
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.collapse()
        #expect(!state.isMorphingArtwork)
        state.applyAnimationTarget()
        let closingToken = state.animationToken
        state.drag(to: 0.1, from: .miniPlayer)
        #expect(state.isMorphingArtwork)
        state.animationDidComplete(token: closingToken)
        #expect(state.isMorphingArtwork)
    }

    @Test func miniPlayerAcceptsContactBeforeClosingAnimationCompletes() {
        let state = NowPlayingPresentation()
        state.expand()
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.collapse()
        state.applyAnimationTarget()
        let closingToken = state.animationToken

        // Exact state from the failed device trace: the mini player is visible,
        // progress is zero, but the closing spring's completion is still pending.
        #expect(state.isAnimatingTransition)
        #expect(state.progress == 0)
        #expect(state.canBeginMiniPlayerContact)
        state.drag(to: 0.01, from: .miniPlayer)
        #expect(state.dragSource == .miniPlayer)
        #expect(state.progress == 0.01)
        #expect(!state.isExpanded)
        #expect(!state.canBeginMiniPlayerContact)
        state.animationDidComplete(token: closingToken)
        #expect(state.dragSource == .miniPlayer)
        #expect(state.progress == 0.01)

        state.endDrag(dismissing: false, from: .miniPlayer)
        state.animationDidComplete(token: closingToken)
        #expect(state.isExpanded)
        #expect(state.isAnimatingTransition)
        #expect(state.animationTarget == 1)
    }

    @Test func closingCanFinishBetweenTouchDownAndFirstMovement() {
        let state = NowPlayingPresentation()
        state.expand()
        state.applyAnimationTarget()
        state.collapse()
        state.applyAnimationTarget()
        #expect(state.canBeginMiniPlayerContact)
        state.animationDidComplete(token: state.animationToken)
        #expect(state.canBeginMiniPlayerContact)
        state.drag(to: 0.1, from: .miniPlayer)
        #expect(state.dragSource == .miniPlayer)
        #expect(state.progress == 0.1)
    }

    @Test func miniPlayerTapCanReversePendingClose() {
        let state = NowPlayingPresentation()
        state.expand()
        #expect(!state.canBeginMiniPlayerContact)
        state.applyAnimationTarget()
        state.collapse()
        state.applyAnimationTarget()
        let closingToken = state.animationToken
        #expect(state.canBeginMiniPlayerContact)
        state.expand()
        state.animationDidComplete(token: closingToken)
        #expect(state.isExpanded)
        #expect(state.isAnimatingTransition)
        #expect(state.animationTarget == 1)
    }

    @Test func tapCannotFinishAnActiveOpeningDrag() {
        let state = NowPlayingPresentation()
        state.drag(to: 0.35, from: .miniPlayer)
        state.expand()
        #expect(state.progress == 0.35)
        #expect(!state.isExpanded)
        #expect(!state.isAnimatingTransition)
    }

    @Test func cancelledOpeningReturnsToMiniPlayer() {
        let state = NowPlayingPresentation()
        state.drag(to: 0.8, from: .miniPlayer)
        state.cancelDrag(from: .miniPlayer)
        #expect(!state.isExpanded)
        #expect(state.animationTarget == 0)
        // A late terminal event must not convert cancellation to a commit.
        state.endDrag(dismissing: false, from: .miniPlayer)
        #expect(!state.isExpanded)
        #expect(state.animationTarget == 0)
    }

    @Test func cancelledClosingReturnsToFullPlayer() {
        let state = NowPlayingPresentation()
        state.expand()
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.drag(to: 0.2, from: .fullPlayer)
        state.cancelDrag(from: .fullPlayer)
        #expect(state.isExpanded)
        #expect(state.animationTarget == 1)
    }

    @Test func offscreenFullPlayerCannotTurnTinyOpeningIntoExpansion() {
        let state = NowPlayingPresentation()
        state.drag(to: 0.01, from: .miniPlayer)
        // The closing recognizer interprets upward movement as progress = 1.
        state.drag(to: 1, from: .fullPlayer)
        state.cancelDrag(from: .fullPlayer)
        state.endDrag(dismissing: false, from: .fullPlayer)
        #expect(state.progress == 0.01)
        #expect(state.dragSource == .miniPlayer)
        #expect(!state.isExpanded)
        #expect(!state.isAnimatingTransition)
    }

    @Test func inactiveRecognizerCannotAcquireADrag() {
        let state = NowPlayingPresentation()
        state.drag(to: 1, from: .fullPlayer)
        #expect(state.progress == 0)
        #expect(!state.isDragging)
        state.expand()
        state.applyAnimationTarget()
        state.animationDidComplete(token: state.animationToken)
        state.drag(to: 0.01, from: .miniPlayer)
        #expect(state.progress == 1)
        #expect(!state.isDragging)
    }
}
