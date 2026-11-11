import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// The upload controller against a stub service and transport: no files are
/// read, no session is created, and nothing reaches a server.
@MainActor
@Suite("Song upload controller")
struct SongUploadControllerTests {
    typealias Event = UploadTransport.Event

    /// A transport whose events the test sends by hand.
    nonisolated final class StubTransport: Sendable {
        struct State {
            var nextTaskID = 100
            var started: [(request: URLRequest, file: URL)] = []
            var cancelled: [Int] = []
            var acknowledged: [Int] = []
            var active: Set<Int> = []
        }

        let state = Mutex(State())
        private let stream: AsyncStream<Event>
        private let continuation: AsyncStream<Event>.Continuation

        init() {
            (stream, continuation) = AsyncStream.makeStream()
        }

        func send(_ event: Event) {
            continuation.yield(event)
        }

        var started: [(request: URLRequest, file: URL)] {
            state.withLock { $0.started }
        }

        var transport: UploadTransport {
            UploadTransport(
                start: { [self] request, file in
                    state.withLock { state in
                        state.nextTaskID += 1
                        state.started.append((request, file))
                        state.active.insert(state.nextTaskID)
                        return state.nextTaskID
                    }
                },
                cancel: { [self] taskID in state.withLock { $0.cancelled.append(taskID) } },
                activeTaskIDs: { [self] in state.withLock { $0.active } },
                events: { [stream] in stream },
                acknowledge: { [self] taskID in state.withLock { $0.acknowledged.append(taskID) } },
                handleBackgroundEvents: {}
            )
        }
    }

    /// The service's closures, with what they were asked.
    @MainActor
    final class Harness {
        let transport = StubTransport()
        let outbox = UploadOutboxStore.inMemory()
        var limits: () throws -> UploadLimits = { Harness.limits(remainingSongs: 10) }
        var limitsCalls = 0
        var songIDs: Set<String> = ["old"]
        var stageCalls = 0
        var staged: [StagedUpload] = []
        var discarded: [UUID] = []
        var invalidations = 0
        var tokenCount = 0
        var importResult: () throws -> SongLinkImportResult? = { nil }
        var importCalls = 0

        nonisolated static func limits(remainingSongs: Int, remainingBytes: Int64 = 1_000_000) -> UploadLimits {
            UploadLimits(
                maxSongs: 50,
                maxStorageBytes: 1_000_000,
                usedStorageBytes: 1_000_000 - remainingBytes,
                currentSongCount: 50 - remainingSongs,
                currentPlaylistCount: 0,
                playlistLimit: 10,
                songPerPlaylistLimit: 100
            )
        }

        var service: SongUploadController.Service {
            SongUploadController.Service(
                limits: { [self] in
                    limitsCalls += 1
                    return try limits()
                },
                uploadedSongIDs: { [self] in songIDs },
                makeUploadRequest: { [self] staged in
                    tokenCount += 1
                    var request = URLRequest(url: URL(fileURLWithPath: "/upload"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer token-\(tokenCount)", forHTTPHeaderField: "Authorization")
                    request.setValue("multipart/form-data; boundary=\(staged.boundary)", forHTTPHeaderField: "Content-Type")
                    return request
                },
                importLink: { [self] _ in
                    importCalls += 1
                    return try importResult()
                },
                transport: transport.transport,
                outbox: outbox,
                stage: { [self] source, _ in
                    stageCalls += 1
                    let id = UUID()
                    let upload = StagedUpload(
                        id: id,
                        fileURL: URL(fileURLWithPath: "/staged/\(id.uuidString).upload"),
                        bodyBytes: 1200,
                        sourceBytes: 1000,
                        filename: source.lastPathComponent,
                        contentType: "audio/mpeg",
                        boundary: "B-\(id.uuidString)"
                    )
                    staged.append(upload)
                    return upload
                },
                discard: { [self] upload in discarded.append(upload.id) },
                fileSize: { _ in 1000 },
                invalidateUploads: { [self] in invalidations += 1 },
                sweepStaged: { _ in }
            )
        }

        func controller(vanishedGrace: Duration = .zero) -> SongUploadController {
            SongUploadController(service: service, vanishedGrace: vanishedGrace)
        }
    }

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

    /// Starts `song` and waits until the transport has its task.
    private func startedUpload(_ controller: SongUploadController, file: URL? = nil) async -> (UUID?, Int) {
        let before = harness.transport.started.count
        let id = controller.uploadFile(at: file ?? song, metadata: metadata)
        await waitUntil { harness.transport.started.count > before && controller.records[id ?? UUID()]?.taskID != nil }
        return (id, controller.records[id ?? UUID()]?.taskID ?? -1)
    }

    private func pending(taskID: Int, known: Set<String>? = ["old"]) -> PendingUpload {
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
        return PendingUpload(staged: staged, taskID: taskID, title: "Away", startedAt: Date(), knownSongIDs: known)
    }

    // MARK: - Quota

    @Test("A full quota fails the upload before anything is staged")
    func quotaBlocksBeforeStaging() async {
        harness.limits = { Harness.limits(remainingSongs: 0) }
        let controller = harness.controller()
        let id = controller.uploadFile(at: song, metadata: metadata)
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.quotaSongs(max: 50)))
        #expect(harness.stageCalls == 0)
        #expect(harness.transport.started.isEmpty)
    }

    @Test("Limits that can't be loaded don't block the upload")
    func limitsFailureDoesNotBlock() async {
        harness.limits = { throw URLError(.timedOut) }
        let controller = harness.controller()
        let (id, _) = await startedUpload(controller)
        #expect(phase(controller, id) == .uploading(0))
        #expect(harness.stageCalls == 1)
    }

    // MARK: - Progress and success

    @Test("Progress moves the upload through its phases to success")
    func progressMovesThroughPhases() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        #expect(controller.uploads.first?.title == "Song")
        #expect(phase(controller, id) == .uploading(0))
        harness.transport.send(.progress(taskID: taskID, fraction: 0.5))
        await waitUntil { phase(controller, id) == .uploading(0.5) }
        harness.transport.send(.progress(taskID: taskID, fraction: 1))
        await waitUntil { phase(controller, id) == .finishing }
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Song"))
    }

    @Test("An empty 200 counts as success")
    func emptySuccessBodyCountsAsSuccess() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Song"))
    }

    @Test("Success drops caches, bumps the counter and cleans up the stage and outbox")
    func successInvalidatesAndBumpsCompletedUploads() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        #expect(harness.outbox.entries().map(\.taskID) == [taskID])
        harness.transport.send(.finished(taskID: taskID, status: 204, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(harness.invalidations == 1)
        #expect(controller.completedUploads == 1)
        let staged = try #require(harness.staged.first)
        #expect(harness.discarded == [staged.id])
        #expect(harness.outbox.entries().isEmpty)
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [taskID] }
    }

    @Test("Success sets the latest completion until it is acknowledged")
    func successSetsLatestCompletion() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(controller.latestCompletion == SongUploadCompletion(itemID: id ?? UUID(), title: "Song", succeeded: true))
        controller.acknowledgeCompletion()
        #expect(controller.latestCompletion == nil)
    }

    // MARK: - Queue

    @Test("Starting the same file again while it is active is ignored")
    func secondStartOfSameFileWhileActiveIsIgnored() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        #expect(controller.uploadFile(at: song, metadata: metadata) == nil)
        #expect(controller.importLink("https://youtu.be/a") != nil)
        #expect(controller.importLink(" https://youtu.be/a ") == nil)
        #expect(controller.uploads.count == 2)
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(controller.uploadFile(at: song, metadata: metadata) != nil)
    }

    @Test("Queued uploads wait and run one at a time")
    func queuedUploadsRunOneAtATime() async {
        let controller = harness.controller()
        let (first, taskID) = await startedUpload(controller)
        let second = controller.uploadFile(at: URL(fileURLWithPath: "/picked/Other.m4a"), metadata: metadata)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(phase(controller, second) == .waiting)
        #expect(harness.transport.started.count == 1)
        harness.transport.send(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { harness.transport.started.count == 2 }
        #expect(phase(controller, first) == .succeeded(title: "Song"))
        await waitUntil { phase(controller, second) == .uploading(0) }
    }

    // MARK: - Cancel and retry

    @Test("Cancelling stops the transfer, discards the stage and drops the item")
    func cancelStopsTransportAndDiscardsStage() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        controller.cancel(try #require(id))
        #expect(controller.uploads.isEmpty)
        await waitUntil { harness.transport.state.withLock { $0.cancelled } == [taskID] }
        #expect(harness.discarded == harness.staged.map(\.id))
        #expect(harness.outbox.entries().isEmpty)
        harness.transport.send(.failed(taskID: taskID, .cancelled))
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [taskID] }
        #expect(controller.latestCompletion == nil)
    }

    @Test("A retry sends the same staged file with a fresh token")
    func retryReusesStagedFileWithFreshToken() async throws {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 503, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        controller.retry(try #require(id))
        await waitUntil { harness.transport.started.count == 2 }
        let started = harness.transport.started
        #expect(started[0].file == started[1].file)
        #expect(started[0].request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(started[1].request.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
        #expect(harness.stageCalls == 1)
        #expect(harness.discarded.isEmpty)
    }

    // MARK: - Failures

    @Test("A 401 checks the session; a working session keeps the server error")
    func unauthorizedChecksSessionBeforeSigningOut() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        #expect(harness.limitsCalls == 1)
        let body = Data(#""Attempted to perform an unauthorized operation.""#.utf8)
        harness.transport.send(.finished(taskID: taskID, status: 401, body: body, contentType: "application/json", retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(harness.limitsCalls == 2)
        let problem = UploadServerProblem(message: "Attempted to perform an unauthorized operation.", fieldErrors: [:])
        #expect(phase(controller, id) == .failed(.server(status: 401, problem: problem)))
    }

    @Test("A 401 with an expired session fails as signed out")
    func unauthorizedWithExpiredSessionFailsSignedOut() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.limits = { throw KaraokeAPIClient.APIError.httpStatus(401) }
        harness.transport.send(.finished(taskID: taskID, status: 401, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.signedOut))
    }

    @Test("A bare-string server error keeps its message")
    func bareStringServerErrorIsKept() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        let body = Data(#""An unexpected error occurred""#.utf8)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: body, contentType: "application/json; charset=utf-8", retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        let problem = UploadServerProblem(message: "An unexpected error occurred", fieldErrors: [:])
        #expect(phase(controller, id) == .failed(.server(status: 500, problem: problem)))
        #expect(controller.latestCompletion?.succeeded == false)
    }

    @Test("A timeout counts as success when the server has a new song")
    func ambiguousTimeoutWithNewServerSongCountsAsSuccess() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.songIDs = ["old", "new"]
        harness.transport.send(.failed(taskID: taskID, .urlError(.timedOut)))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Song"))
        #expect(controller.completedUploads == 1)
    }

    @Test("A timeout without a new song is a retryable failure")
    func ambiguousTimeoutWithoutNewSongIsRetryable() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.failed(taskID: taskID, .urlError(.timedOut)))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.timedOut))
        #expect(SongUploadFailure.timedOut.isRetryable)
        #expect(controller.completedUploads == 0)
    }

    @Test("A 429 carries the server's Retry-After")
    func rateLimitCarriesRetryAfter() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 429, body: Data(), contentType: nil, retryAfter: 30))
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .failed(.rateLimited(retryAfter: 30)))
    }

    @Test("A failed POST is never sent again on its own")
    func postIsNeverRetriedAutomatically() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        harness.transport.send(.finished(taskID: taskID, status: 500, body: Data(), contentType: nil, retryAfter: nil))
        await waitUntil { isFinished(controller, id) }
        let (other, otherTask) = await startedUpload(controller, file: URL(fileURLWithPath: "/picked/B.mp3"))
        harness.transport.send(.failed(taskID: otherTask, .urlError(.networkConnectionLost)))
        await waitUntil { isFinished(controller, other) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.transport.started.count == 2)
        #expect(phase(controller, other) == .failed(.interrupted))
    }

    // MARK: - Links

    @Test("A link import succeeds with the server's title")
    func linkImportSucceedsWithServerTitle() async {
        harness.importResult = { SongLinkImportResult(success: true, songID: "s-1", title: "Server Title") }
        let controller = harness.controller()
        let id = controller.importLink("https://cdn.discordapp.com/attachments/1/2/a.mp3?ex=1&hm=2")
        await waitUntil { isFinished(controller, id) }
        #expect(phase(controller, id) == .succeeded(title: "Server Title"))
        #expect(controller.uploads.first?.kind == .link)
        #expect(controller.completedUploads == 1)
        #expect(harness.importCalls == 1)
        #expect(harness.transport.started.isEmpty)
    }

    @Test("An unsupported link fails before any request")
    func unsupportedLinkFailsBeforeAnyRequest() async {
        let controller = harness.controller()
        let id = controller.importLink("https://discord.com/channels/1/2/3")
        #expect(phase(controller, id) == .failed(.unsupportedLink(.discordMessageLink)))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(harness.importCalls == 0)
        #expect(harness.limitsCalls == 0)
    }

    // MARK: - Relaunch

    @Test("After a relaunch, an upload the session still runs shows as uploading")
    func resumeShowsUploadStillRunning() async {
        harness.outbox.save(pending(taskID: 7))
        harness.transport.state.withLock { $0.active = [7] }
        let controller = harness.controller()
        await controller.resume()
        #expect(controller.uploads.map(\.title) == ["Away"])
        #expect(controller.uploads.first?.phase == .uploading(0))
        harness.transport.send(.progress(taskID: 7, fraction: 0.5))
        await waitUntil { controller.uploads.first?.phase == .uploading(0.5) }
    }

    @Test("After a relaunch, an upload that finished while away completes")
    func resumeCompletesUploadThatFinishedWhileAway() async {
        harness.outbox.save(pending(taskID: 8))
        harness.transport.send(.finished(taskID: 8, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        let controller = harness.controller(vanishedGrace: .seconds(1))
        await controller.resume()
        await waitUntil { controller.uploads.first?.phase.isFinished == true }
        #expect(controller.uploads.first?.phase == .succeeded(title: "Away"))
        #expect(controller.completedUploads == 1)
        #expect(harness.outbox.entries().isEmpty)
        await waitUntil { harness.transport.state.withLock { $0.acknowledged } == [8] }
    }

    @Test("After a relaunch, a vanished task without a new song fails retryably")
    func resumeFailsVanishedTaskWithoutNewSong() async {
        harness.outbox.save(pending(taskID: 9))
        let controller = harness.controller()
        await controller.resume()
        await waitUntil { controller.uploads.first?.phase.isFinished == true }
        #expect(controller.uploads.first?.phase == .failed(.interrupted))
        #expect(harness.outbox.entries().isEmpty)
        #expect(harness.discarded.isEmpty)
    }
}
