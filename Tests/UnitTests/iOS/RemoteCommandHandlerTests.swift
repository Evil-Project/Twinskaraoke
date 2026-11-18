import Foundation
import MediaPlayer
import Synchronization
import Testing
@testable import Twinskaraoke

@Suite("Remote command handlers")
struct RemoteCommandHandlerTests {
    @Test("A command delivered off the main thread runs on the main actor and returns its status")
    func backgroundDeliveryHopsToMain() async {
        let ranOnMain = Mutex<Bool?>(nil)
        let handler: @Sendable (Int) -> MPRemoteCommandHandlerStatus = RemoteCommandHandler.make {
            ranOnMain.withLock { $0 = Thread.isMainThread }
            return .noActionableNowPlayingItem
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<MPRemoteCommandHandlerStatus, Never>) in
            DispatchQueue.global().async { continuation.resume(returning: handler(0)) }
        }

        #expect(status == .noActionableNowPlayingItem)
        #expect(ranOnMain.withLock { $0 } == true)
    }

    @Test("A command delivered on the main thread runs before the handler returns")
    @MainActor
    func mainThreadDeliveryRunsInline() {
        let ran = Mutex(false)
        let handler: @Sendable (Int) -> MPRemoteCommandHandlerStatus = RemoteCommandHandler.make {
            ran.withLock { $0 = true }
            return .success
        }

        #expect(handler(0) == .success)
        #expect(ran.withLock { $0 })
    }

    @Test("The event value is read on the delivering thread and handed to the main actor")
    func extractedValueCrossesToMain() async {
        let extractedOnMain = Mutex<Bool?>(nil)
        let received = Mutex<(value: Double, onMain: Bool)?>(nil)
        let handler: @Sendable (Double) -> MPRemoteCommandHandlerStatus = RemoteCommandHandler.make(extracting: { event in
            extractedOnMain.withLock { $0 = Thread.isMainThread }
            return event
        }, perform: { value in
            received.withLock { $0 = (value, Thread.isMainThread) }
            return .success
        })

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<MPRemoteCommandHandlerStatus, Never>) in
            DispatchQueue.global().async { continuation.resume(returning: handler(42)) }
        }

        #expect(status == .success)
        #expect(extractedOnMain.withLock { $0 } == false)
        #expect(received.withLock { $0?.value } == 42)
        #expect(received.withLock { $0?.onMain } == true)
    }

    @Test("An event without a usable value fails without running the action")
    func missingValueFailsTheCommand() {
        let ran = Mutex(false)
        let handler: @Sendable (Double) -> MPRemoteCommandHandlerStatus = RemoteCommandHandler.make(extracting: { event in
            event.isFinite ? event : nil
        }, perform: { _ in
            ran.withLock { $0 = true }
            return .success
        })

        #expect(handler(.nan) == .commandFailed)
        #expect(!ran.withLock { $0 })
    }
}
