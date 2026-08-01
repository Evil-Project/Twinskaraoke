import Testing
@testable import Twinskaraoke

@Suite("Latest load ownership")
struct LatestLoadOwnershipGateTests {
    @Test("A replaced load cannot finish the current request")
    func staleCompletionIsRejected() {
        var gate = LatestLoadOwnershipGate()
        let replaced = gate.begin()
        let active = gate.begin()
        let acceptedReplacedCompletion = gate.finish(replaced)
        let acceptedActiveCompletion = gate.finish(active)

        #expect(!acceptedReplacedCompletion)
        #expect(acceptedActiveCompletion)
    }

    @Test("Cancellation invalidates the active load")
    func cancellationInvalidatesActiveLoad() {
        var gate = LatestLoadOwnershipGate()
        let load = gate.begin()
        let cancelledLoad = gate.cancel()
        let acceptedCancelledCompletion = gate.finish(load)

        #expect(cancelledLoad == load)
        #expect(!acceptedCancelledCompletion)
    }

    @Test("A load completion is consumed only once")
    func completionIsConsumedOnce() {
        var gate = LatestLoadOwnershipGate()
        let load = gate.begin()
        let acceptedFirstCompletion = gate.finish(load)
        let acceptedDuplicateCompletion = gate.finish(load)

        #expect(acceptedFirstCompletion)
        #expect(!acceptedDuplicateCompletion)
    }
}
