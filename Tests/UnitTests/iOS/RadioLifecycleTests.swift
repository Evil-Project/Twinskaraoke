import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Radio refresh lifecycle")
struct RadioLifecycleTests {
    @Test("Stopping and restarting cannot let an old refresh clear the new spinner")
    func supersededRefresh() async {
        var responses: [CheckedContinuation<Data, Never>] = []
        let controller = RadioController(loadMetadata: {
            await withCheckedContinuation { responses.append($0) }
        })
        let first = Task { await controller.refresh() }
        while responses.count < 1 { await Task.yield() }
        #expect(controller.isRefreshing)
        controller.stop()
        #expect(!controller.isRefreshing)

        let second = Task { await controller.refresh() }
        while responses.count < 2 { await Task.yield() }
        responses[0].resume(returning: Data())
        await first.value
        #expect(controller.isRefreshing)
        #expect(controller.refreshErrorMessage == nil)

        controller.stop()
        responses[1].resume(returning: Data())
        await second.value
        #expect(!controller.isRefreshing)
        #expect(controller.refreshErrorMessage == nil)
    }
}
