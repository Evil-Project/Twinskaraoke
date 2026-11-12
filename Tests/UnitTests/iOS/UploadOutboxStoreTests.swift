import Foundation
import Testing
@testable import Twinskaraoke

/// The pending-upload journal, in temporary folders.
@Suite("Upload outbox")
struct UploadOutboxStoreTests {
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadOutboxStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("outbox.json")
    }

    private static func upload(taskID: Int?, title: String = "Song") -> PendingUpload {
        let id = UUID()
        let staged = StagedUpload(
            id: id,
            fileURL: UploadStaging.fileURL(for: id),
            bodyBytes: 1200,
            sourceBytes: 1000,
            filename: "song.mp3",
            contentType: "audio/mpeg",
            boundary: "B-\(id.uuidString)"
        )
        return PendingUpload(
            staged: staged,
            taskID: taskID,
            title: title,
            startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            knownSongIDs: ["a", "b"]
        )
    }

    @Test("Pending uploads survive a new store reading the same file")
    func outboxRoundTripsPendingUploads() throws {
        let first = Self.upload(taskID: 4, title: "ネウロ")
        var second = Self.upload(taskID: nil)
        let store = UploadOutboxStore(fileURL: fileURL)
        store.save(first)
        store.save(second)
        second.taskID = 9
        store.save(second)

        let reopened = UploadOutboxStore(fileURL: fileURL)
        #expect(reopened.entries() == [first, second])
        let staged = first.staged(in: fileURL.deletingLastPathComponent())
        #expect(staged.id == first.id)
        #expect(staged.boundary == first.boundary)
        #expect(staged.sourceBytes == 1000)
        #expect(staged.bodyBytes == 1200)
    }

    @Test("A corrupt file or another version reads as empty")
    func outboxIgnoresCorruptOrOldVersionFile() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: fileURL)
        #expect(UploadOutboxStore(fileURL: fileURL).entries().isEmpty)

        let store = UploadOutboxStore(fileURL: fileURL)
        store.save(Self.upload(taskID: 1))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        json["version"] = 0
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL)
        #expect(UploadOutboxStore(fileURL: fileURL).entries().isEmpty)

        let missing = fileURL.deletingLastPathComponent().appendingPathComponent("none.json")
        #expect(UploadOutboxStore(fileURL: missing).entries().isEmpty)
    }

    @Test("A finished upload is removed and stays removed")
    func outboxRemovesFinishedUpload() {
        let done = Self.upload(taskID: 1)
        let running = Self.upload(taskID: 2)
        let store = UploadOutboxStore(fileURL: fileURL)
        store.save(done)
        store.save(running)
        store.remove(id: done.id)
        #expect(store.entries() == [running])
        #expect(UploadOutboxStore(fileURL: fileURL).entries() == [running])

        let memory = UploadOutboxStore.inMemory()
        memory.save(done)
        memory.remove(id: done.id)
        #expect(memory.entries().isEmpty)
    }

    @Test("The live store is one shared instance")
    func liveStoreIsShared() {
        #expect(UploadOutboxStore.live === UploadOutboxStore.live)
    }
}
