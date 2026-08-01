import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Transition predownload completion ownership")
struct PredownloadCompletionGateTests {
    @Test("Concurrent completion paths can claim the continuation only once")
    func concurrentClaimsAreOneShot() async {
        let gate = PredownloadCompletionGate(completion: {})

        let claimCount = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    gate.take() == nil ? 0 : 1
                }
            }

            var count = 0
            for await claimed in group {
                count += claimed
            }
            return count
        }

        #expect(claimCount == 1)
        #expect(gate.take() == nil)
    }
}
