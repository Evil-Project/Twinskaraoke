import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// Uploads that end while the app isn't active get the local notification
/// downloads get. The notifier is a stub: nothing reaches the system.
@MainActor
@Suite("Song upload notifications")
struct SongUploadNotificationTests {
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

    @MainActor
    private final class Flag {
        var value = false
    }

    private func finish(_ taskID: Int, status: Int = 200) {
        harness.transport.send(.finished(taskID: taskID, status: status, body: Data(), contentType: nil, retryAfter: nil))
    }

    @Test("An upload that finishes in the background notifies with the song's title")
    func notifiesWhenUploadFinishesInBackground() async throws {
        harness.appIsActive = false
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        finish(taskID)
        await waitUntil { harness.notifications.count == 1 }
        let content = try #require(harness.notifications.first)
        #expect(content.body.contains("Song"))
        #expect(content.body != UploadNotifier.content(
            for: SongUploadCompletion(itemID: try #require(id), title: "Song", succeeded: false)
        ).body)
        #expect(content.identifier.hasSuffix(try #require(id).uuidString))
    }

    @Test("No notification while the app is active")
    func doesNotNotifyWhileAppIsActive() async {
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        finish(taskID)
        await waitUntil { isFinished(controller, id) }
        // Any notification would be posting by now; wait for those to end.
        await controller.finishNotifications()
        #expect(harness.notifications.isEmpty)
    }

    @Test("No notification when the setting is off")
    func doesNotNotifyWhenSettingIsOff() async {
        harness.appIsActive = false
        harness.notificationsEnabled = false
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        finish(taskID)
        await waitUntil { isFinished(controller, id) }
        // Any notification would be posting by now; wait for those to end.
        await controller.finishNotifications()
        #expect(harness.notifications.isEmpty)
    }

    @Test("A failure says the song couldn't be uploaded")
    func failureNotificationNamesTheSong() async throws {
        harness.appIsActive = false
        let controller = harness.controller()
        let (id, taskID) = await startedUpload(controller)
        finish(taskID, status: 400)
        await waitUntil { harness.notifications.count == 1 }
        let content = try #require(harness.notifications.first)
        let expected = UploadNotifier.content(
            for: SongUploadCompletion(itemID: try #require(id), title: "Song", succeeded: false)
        )
        #expect(content == expected)
        #expect(content.body.contains("Song"))
    }

    @Test("One notification per upload")
    func notifiesOncePerUpload() async {
        harness.appIsActive = false
        let controller = harness.controller()
        let (first, taskID) = await startedUpload(controller)
        finish(taskID)
        // The session repeats the answer: nothing new to say.
        finish(taskID)
        await waitUntil { isFinished(controller, first) }
        let (_, otherTask) = await startedUpload(controller, file: URL(fileURLWithPath: "/picked/Other.m4a"))
        finish(otherTask, status: 400)
        await waitUntil { harness.notifications.count == 2 }
        await controller.finishNotifications()
        #expect(harness.notifications.count == 2)
        #expect(Set(harness.notifications.map(\.identifier)).count == 2)
    }

    @Test("A link import that ends in the background notifies too")
    func linkImportNotifies() async {
        harness.appIsActive = false
        harness.importResult = { SongLinkImportResult(success: true, songID: "s", title: "Linked") }
        let controller = harness.controller()
        let id = controller.importLink("https://youtu.be/a")
        await waitUntil { isFinished(controller, id) }
        await waitUntil { harness.notifications.count == 1 }
        #expect(harness.notifications.first?.body.contains("Linked") == true)
    }

    @Test("An upload settled during a background wake notifies before the wake ends")
    func backgroundWakeCompletionNotifies() async {
        harness.appIsActive = false
        var release: CheckedContinuation<Void, Never>?
        harness.deliveryHold = { await withCheckedContinuation { release = $0 } }
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
        harness.outbox.save(PendingUpload(
            staged: staged, taskID: 8, title: "Away", startedAt: Date(), knownSongIDs: ["old"], account: "account-a"
        ))
        harness.transport.send(.finished(taskID: 8, status: 200, body: Data(), contentType: nil, retryAfter: nil))
        let controller = harness.controller(vanishedGrace: .seconds(1))
        await waitUntil { controller.uploads.first?.phase.isFinished == true && release != nil }

        // Still being posted: the wake waits for it before it ends.
        let wakeEnded = Flag()
        let wake = Task {
            await controller.handleBackgroundEvents()
            wakeEnded.value = true
        }
        await waitUntil { harness.transport.state.withLock { $0.backgroundEventsHandled } == 1 }
        #expect(!wakeEnded.value)
        #expect(harness.notifications.isEmpty)

        release?.resume()
        await wake.value
        #expect(wakeEnded.value)
        #expect(harness.notifications.count == 1)
        #expect(harness.notifications.first?.body.contains("Away") == true)
    }
}
