import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Audio session activation")
struct AudioSessionControllerTests {
    @Test func synchronousFallbackRunsOffMainThread() async {
        let succeeded = await withCheckedContinuation { continuation in
            AudioSessionController.activateInBackground({
                #expect(!Thread.isMainThread)
            }, completion: { activated, error in
                #expect(error == nil)
                continuation.resume(returning: activated)
            })
        }
        #expect(succeeded)
    }

    @Test func synchronousFallbackPreservesActivationError() async {
        let result = await withCheckedContinuation { continuation in
            AudioSessionController.activateInBackground({
                throw NSError(domain: "activation-fixture", code: 42)
            }, completion: { activated, error in
                continuation.resume(returning: (activated, error as NSError?))
            })
        }
        #expect(!result.0)
        #expect(result.1?.domain == "activation-fixture")
        #expect(result.1?.code == 42)
    }

    private final class ActivationProbe {
        var completions: [@Sendable (Bool, (any Error)?) -> Void] = []
        var configurations = 0
        lazy var controller = AudioSessionController(configure: { [unowned self] in
            configurations += 1
        }, activate: { [unowned self] completion in
            completions.append(completion)
        })
    }

    @Test func configuringTheCategoryDoesNotActivate() async {
        let probe = ActivationProbe()
        probe.controller.configureCategory()
        probe.controller.configureCategory()
        #expect(probe.configurations == 1)
        #expect(probe.completions.isEmpty)

        var played = false
        #expect(!probe.controller.performWhenReady { played = true })
        #expect(probe.completions.count == 1)
        #expect(probe.configurations == 1)
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played)
    }

    @Test func waitsForActivationAndCoalescesPlayback() async {
        let probe = ActivationProbe()
        var played: [Int] = []
        #expect(!probe.controller.performWhenReady { played.append(1) })
        #expect(!probe.controller.performWhenReady { played.append(2) })
        #expect(played.isEmpty)
        #expect(probe.completions.count == 1)
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played == [2])
        #expect(!probe.controller.hasPendingPlayback)
        #expect(probe.controller.performWhenReady { played.append(3) })
        #expect(played == [2]) // Active callers execute their operation inline.
    }

    @Test func backgroundPreparationCannotReplaceUserPlay() async {
        let probe = ActivationProbe()
        var played: [Int] = []
        #expect(!probe.controller.performWhenReady { played.append(1) })
        let ready = probe.controller.performWhenReady({ played.append(2) }, replacingPending: false)
        #expect(!ready)
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played == [1])
    }

    @Test func pausePreventsLateActivationFromPlaying() async {
        let probe = ActivationProbe()
        var played = false
        #expect(!probe.controller.performWhenReady { played = true })
        probe.controller.cancelPendingPlayback()
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(!played)
        #expect(!probe.controller.hasPendingPlayback)
    }

    @Test func latePreparationCannotUndoPauseDuringActivation() async {
        let probe = ActivationProbe()
        var played: [Int] = []
        #expect(!probe.controller.performWhenReady { played.append(1) })
        probe.controller.cancelPendingPlayback()
        let ready = probe.controller.performWhenReady({ played.append(2) }, replacingPending: false)
        #expect(!ready)
        #expect(!probe.controller.hasPendingPlayback)
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played.isEmpty)
        #expect(probe.controller.performWhenReady { played.append(3) })
    }

    @Test func explicitPlayAfterPauseCanUsePendingActivation() async {
        let probe = ActivationProbe()
        var played: [Int] = []
        #expect(!probe.controller.performWhenReady { played.append(1) })
        probe.controller.cancelPendingPlayback()
        #expect(!probe.controller.performWhenReady { played.append(2) })
        #expect(probe.completions.count == 1)
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played == [2])
    }

    @Test func interruptedActivationCannotCompleteNewRequest() async {
        let probe = ActivationProbe()
        var played: [Int] = []
        #expect(!probe.controller.performWhenReady { played.append(1) })
        probe.controller.markInterrupted()
        #expect(!probe.controller.performWhenReady { played.append(2) })
        probe.completions[0](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played.isEmpty)
        #expect(probe.controller.hasPendingPlayback)
        probe.completions[1](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played == [2])
    }

    @Test func failedActivationCanRetryAndResetReconfigures() async {
        let probe = ActivationProbe()
        var played = false
        #expect(!probe.controller.performWhenReady { played = true })
        probe.completions[0](false, NSError(domain: "fixture", code: 1))
        for _ in 0..<20 { await Task.yield() }
        #expect(!played)
        #expect(!probe.controller.hasPendingPlayback)
        probe.controller.resetAfterMediaServicesLoss()
        #expect(!probe.controller.performWhenReady { played = true })
        #expect(probe.configurations == 2)
        probe.completions[1](true, nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(played)
    }
}
