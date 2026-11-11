import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// Outcomes that don't say whether the song arrived, and the moments an
/// upload can no longer be cancelled.
@MainActor
@Suite("Song upload settling")
struct SongUploadSettlingTests {
    typealias Harness = SongUploadControllerTests.Harness

    private let harness = Harness()
    private let song = URL(fileURLWithPath: "/picked/Song.mp3")
    private let metadata = SongUploadMetadata(title: "", artist: "Neuro", playlistID: nil)

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<2000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "timed out", sourceLocation: sourceLocation)
    }

    private func phase(_ controller: SongUploadController, _ id: UUID?) -> SongUploadItem.Phase? {
        controller.uploads.first { $0.id == id }?.phase
    }

    private func isFinished(_ controller: SongUploadController, _ id: UUID?) -> Bool {
        phase(controller, id)?.isFinished == true
    }

    /// Starts `file` and waits until the transport has its task.
    private func startedUpload(_ controller: SongUploadController, file: URL? = nil) async -> (UUID?, Int) {
        let before = harness.transport.started.count
        let id = controller.uploadFile(at: file ?? song, metadata: metadata)
        await waitUntil { harness.transport.started.count > before && controller.records[id ?? UUID()]?.taskID != nil }
        return (id, controller.records[id ?? UUID()]?.taskID ?? -1)
    }

    private func failedWithServerError(_ phase: SongUploadItem.Phase?, status: Int) -> Bool {
        if case let .failed(.server(actual, _)) = phase { actual == status } else { false }
    }

    // MARK: - Server errors

    @Test("A 5xx counts as success when the server has a new song")
    func serverErrorWithNewSongCountsAsSuccess() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.songIDs = ["old", "new"]
        harness.transport.send(.finished(taskID: taskID, status: 503, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Song"))
        #expect(harness.discarded == [try #require(harness.staged.first).id])
        #expect(controller.completedUploads == 1)
    }

    @Test("A 5xx without a new song fails and keeps the body for a retry")
    func serverErrorWithoutNewSongFails() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(failedWithServerError(phase(controller, id), status: 500))
        #expect(harness.discarded.isEmpty)
        controller.retry(try #require(id))
        await waitUntil { harness.transport.started.count == 2 }
    }

    @Test("A 4xx fails without asking the server's list")
    func clientErrorFailsAtOnce() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.songIDs = ["old", "new"]
        harness.transport.send(.finished(taskID: taskID, status: 400, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(failedWithServerError(phase(controller, id), status: 400))
    }

    // MARK: - Cancel

    @Test("Cancel is ignored once the server's answer arrived")
    func cancelIsIgnoredOnceTheAnswerArrived() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        var release: CheckedContinuation<Void, Never>?
        harness.invalidationHold = { await withCheckedContinuation { release = $0 } }
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { release != nil }

        controller.cancel(try #require(id))
        #expect(phase(controller, id) == .finishing)
        release?.resume()
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Song"))
        #expect(controller.completedUploads == 1)
        #expect(harness.transport.state.withLock { $0.cancelled }.isEmpty)
    }

    // MARK: - Background wake

    @Test("A background wake with an empty outbox acknowledges orphan events")
    func backgroundWakeWithEmptyOutboxAcknowledgesOrphanEvents() async {
        harness.transport.send(.finished(taskID: 9, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        let controller = harness.controller()
        await controller.handleBackgroundEvents()
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [9] }
        #expect(controller.uploads.isEmpty)
    }

    // MARK: - Link imports

    @Test("An interrupted link import that landed counts as success")
    func interruptedLinkImportThatLandedSucceeds() async {
        harness.importResult = { [harness] in
            harness.songIDs.insert("new")
            throw URLError(.cancelled)
        }
        let controller = harness.controller()
        let id = controller.importLink("https://youtu.be/a")
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "https://youtu.be/a"))
        #expect(controller.completedUploads == 1)
    }

    @Test("An interrupted link import without a new song fails retryably")
    func interruptedLinkImportWithoutNewSongFails() async {
        harness.importResult = { throw URLError(.cancelled) }
        let controller = harness.controller()
        let id = controller.importLink("https://youtu.be/a")
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.interrupted))
        #expect(controller.completedUploads == 0)
    }

    @Test("A timed-out or 5xx link import that landed counts as success")
    func timedOutLinkImportThatLandedSucceeds() async {
        for failure in [SongUploadFailure.timedOut, .server(status: 504, problem: nil)] {
            harness.songIDs = ["old"]
            harness.importResult = { [harness] in
                harness.songIDs.insert("new")
                throw failure
            }
            let controller = harness.controller()
            let id = controller.importLink("https://youtu.be/a")
            await waitUntil { isFinished(controller, id) }
            #expect(phase(controller, id) == .succeeded(title: "https://youtu.be/a"), "\(failure)")
        }
    }

    @Test("A link import the server refused fails without asking the list")
    func refusedLinkImportFails() async {
        harness.importResult = { [harness] in
            harness.songIDs.insert("new")
            throw SongUploadFailure.server(status: 400, problem: nil)
        }
        let controller = harness.controller()
        let id = controller.importLink("https://youtu.be/a")
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.server(status: 400, problem: nil)))
    }
}
