import Testing
@testable import Twinskaraoke

@Suite("Transition predownload lifecycle")
struct PredownloadLifecycleStateTests {
    @Test("Cancellation during validation prevents the validation from finishing")
    func cancellationWinsDuringValidation() {
        var lifecycle = PredownloadLifecycleState()

        #expect(lifecycle.phase == .running)
        let didBeginValidation = lifecycle.beginValidation()
        #expect(didBeginValidation)
        #expect(lifecycle.phase == .validating)
        let didCancel = lifecycle.cancel()
        #expect(didCancel)
        #expect(lifecycle.phase == .cancelled)
        let didFinishValidation = lifecycle.finishValidation()
        #expect(!didFinishValidation)
        #expect(lifecycle.phase == .cancelled)
    }

    @Test("A finished validation cannot be cancelled afterward")
    func validationFinishWinsBeforeCancellation() {
        var lifecycle = PredownloadLifecycleState()

        let didBeginValidation = lifecycle.beginValidation()
        #expect(didBeginValidation)
        let didFinishValidation = lifecycle.finishValidation()
        #expect(didFinishValidation)
        #expect(lifecycle.phase == .finished)
        let didCancel = lifecycle.cancel()
        #expect(!didCancel)
        #expect(lifecycle.phase == .finished)
    }

    @Test("Cancellation from running prevents every completion path")
    func cancellationBeforeValidationIsTerminal() {
        var lifecycle = PredownloadLifecycleState()

        let didCancel = lifecycle.cancel()
        #expect(didCancel)
        #expect(lifecycle.phase == .cancelled)
        let didBeginValidation = lifecycle.beginValidation()
        #expect(!didBeginValidation)
        let didFinishValidation = lifecycle.finishValidation()
        #expect(!didFinishValidation)
        let didFinishWithoutValidation = lifecycle.finishWithoutValidation()
        #expect(!didFinishWithoutValidation)
        #expect(lifecycle.phase == .cancelled)
    }

    @Test("Finishing without validation is terminal")
    func finishWithoutValidationIsTerminal() {
        var lifecycle = PredownloadLifecycleState()

        let invalidValidationFinish = lifecycle.finishValidation()
        #expect(!invalidValidationFinish)
        #expect(lifecycle.phase == .running)
        let didFinishWithoutValidation = lifecycle.finishWithoutValidation()
        #expect(didFinishWithoutValidation)
        #expect(lifecycle.phase == .finished)
        let didBeginValidation = lifecycle.beginValidation()
        #expect(!didBeginValidation)
        let didCancel = lifecycle.cancel()
        #expect(!didCancel)
        let didFinishAgain = lifecycle.finishWithoutValidation()
        #expect(!didFinishAgain)
        #expect(lifecycle.phase == .finished)
    }
}
