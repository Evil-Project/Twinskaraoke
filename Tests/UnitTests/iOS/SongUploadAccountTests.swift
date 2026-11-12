import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// Every upload belongs to the account that started it: it is never sent,
/// imported or retried under another one, and leaves the list when the
/// account changes.
@MainActor
@Suite("Song upload accounts")
struct SongUploadAccountTests {
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

    private func pending(taskID: Int, account: String?) -> PendingUpload {
        let id = UUID()
        let staged = StagedUpload(
            id: id,
            fileURL: URL(fileURLWithPath: "/staged/\(id.uuidString).upload"),
            bodyBytes: 1200,
            sourceBytes: 1000,
            filename: "Song.mp3",
            contentType: "audio/mpeg",
            boundary: "B"
        )
        return PendingUpload(
            staged: staged, taskID: taskID, title: "Away", startedAt: Date(), knownSongIDs: ["old"], account: account
        )
    }

    // MARK: - Relaunch

    @Test("After a relaunch, another account's ended upload is dropped with its body")
    func restoreDropsAnotherAccountsEndedUpload() async {
        let entry = pending(taskID: 9, account: "account-a")
        harness.outbox.save(entry)
        harness.account = "account-b"
        let controller = harness.controller()
        await controller.resume()
        #expect(controller.uploads.isEmpty)
        #expect(controller.records.isEmpty)
        #expect(harness.outbox.entries().isEmpty)
        #expect(harness.discarded == [entry.id])
    }

    @Test("After a relaunch, another account's running transfer finishes unseen")
    func restoreFinishesAnotherAccountsTransferUnseen() async {
        let entry = pending(taskID: 7, account: "account-a")
        harness.outbox.save(entry)
        harness.transport.state.withLock { $0.active = [7] }
        harness.account = "account-b"
        let controller = harness.controller()
        await controller.resume()
        #expect(controller.uploads.isEmpty)
        #expect(harness.discarded.isEmpty)

        harness.transport.send(.progress(taskID: 7, fraction: 1))
        harness.transport.send(.finished(taskID: 7, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [7] }
        #expect(controller.uploads.isEmpty)
        #expect(controller.latestCompletion == nil)
        #expect(controller.completedUploads == 0)
        #expect(harness.invalidations == 0)
        #expect(harness.outbox.entries().isEmpty)
        #expect(harness.discarded == [entry.id])
        #expect(controller.records.isEmpty)
    }

    @Test("After a relaunch, an upload still shows when either account can't be told")
    func restoreKeepsUploadWhenAccountUnknown() async {
        harness.outbox.save(pending(taskID: 7, account: "account-a"))
        harness.outbox.save(pending(taskID: 8, account: nil))
        harness.transport.state.withLock { $0.active = [7, 8] }
        harness.account = nil
        let first = harness.controller()
        await first.resume()
        #expect(first.uploads.count == 2)

        harness.account = "account-b"
        let second = harness.controller()
        await second.resume()
        #expect(second.uploads.map(\.title) == ["Away"])
    }

    // MARK: - Sending

    @Test("A queued upload isn't sent after the account changed")
    func queuedUploadIsNotSentAfterAccountChange() async {
        let controller = harness.controller()
        let (first, taskID) = await startedUpload(controller)
        #expect(harness.outbox.entries().first?.account == "account-a")
        let second = controller.uploadFile(at: URL(fileURLWithPath: "/picked/Other.m4a"), metadata: metadata)
        harness.account = "account-b"
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, first) && isFinished(controller, second) }
        #expect(phase(controller, second) == .failed(.signedOut))
        #expect(harness.transport.started.count == 1)
        #expect(harness.stageCalls == 1)
    }

    @Test("A link queued by one account isn't imported for another")
    func queuedLinkIsNotImportedAfterAccountChange() async {
        let controller = harness.controller()
        let (first, taskID) = await startedUpload(controller)
        let link = controller.importLink("https://youtu.be/a")
        harness.account = "guest"
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, first) && isFinished(controller, link) }
        #expect(phase(controller, link) == .failed(.signedOut))
        #expect(harness.importCalls == 0)
    }

    @Test("A retry after the account changed is refused")
    func retryAfterAccountChangeIsRefused() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        harness.account = "account-b"
        // The refusal is synchronous: nothing is queued, so nothing can start.
        controller.retry(try #require(id))
        #expect(phase(controller, id) == .failed(.signedOut))
        #expect(harness.transport.started.count == 1)
    }

    @Test("An account that can't be told doesn't block the upload")
    func unknownAccountDoesNotBlock() async {
        harness.account = nil
        let controller = harness.controller()
        let (id, _) = await startedUpload(controller)
        #expect(phase(controller, id) == .uploading(0))
    }

    @Test("An upload isn't sent while the signed-in account can't be read, and can be retried")
    func unreadableAccountAtSendFailsRetryably() async throws {
        let controller = harness.controller()
        let id = controller.uploadFile(at: song, metadata: metadata)
        // Started by account-a; by the time it would send, the Keychain can't tell.
        harness.account = nil
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.interrupted))
        #expect(SongUploadFailure.interrupted.isRetryable)
        #expect(harness.stageCalls == 0)
        #expect(harness.transport.started.isEmpty)

        harness.account = "account-a"
        let link = controller.importLink("https://youtu.be/a")
        harness.account = nil
        await waitUntil { isFinished(controller, link) }
        #expect(phase(controller, link) == .failed(.interrupted))
        #expect(harness.importCalls == 0)

        harness.account = "account-a"
        controller.retry(try #require(id))
        await waitUntil { harness.transport.started.count == 1 }
    }

    @Test("A session change drops the previous account's ended and waiting uploads")
    func accountChangeDropsPreviousAccountsEndedUploads() async throws {
        let controller = harness.controller()
        let (failed, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, failed) }
        let (running, _) = await startedUpload(controller, file: URL(fileURLWithPath: "/picked/B.mp3"))
        let waiting = controller.uploadFile(at: URL(fileURLWithPath: "/picked/C.mp3"), metadata: metadata)
        #expect(controller.uploads.count == 3)

        harness.account = "account-b"
        NotificationCenter.default.post(name: WatchSessionLink.sessionChanged, object: nil)
        await waitUntil { controller.uploads.count == 1 }

        #expect(controller.uploads.map(\.id) == [try #require(running)])
        #expect(controller.records[try #require(failed)] == nil)
        #expect(controller.records[try #require(waiting)] == nil)
        // The failed upload's staged body is gone with it.
        #expect(harness.discarded == [harness.staged[0].id])
        #expect(controller.latestCompletion == nil)
    }

    @Test("A transfer already sent by the previous account leaves the list when it ends")
    func runningTransferOfPreviousAccountLeavesWhenItEnds() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.account = "account-b"
        controller.accountMayHaveChanged()
        // Sent with the previous account's token; it keeps going.
        #expect(phase(controller, id) == .uploading(0))
        #expect(harness.transport.state.withLock { $0.cancelled }.isEmpty)

        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { controller.uploads.isEmpty }
        #expect(controller.latestCompletion == nil)
        #expect(harness.outbox.entries().isEmpty)
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [taskID] }
    }

    @Test("The same account signing in again keeps its uploads")
    func sameAccountKeepsItsUploads() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        controller.accountMayHaveChanged()
        #expect(controller.uploads.map(\.id) == [id])
    }
}
