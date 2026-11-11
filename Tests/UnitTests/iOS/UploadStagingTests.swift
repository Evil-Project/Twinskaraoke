import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// Staging writes multipart bodies to temporary folders; nothing is sent.
@Suite("Upload staging")
struct UploadStagingTests {
    private let directory: URL
    private let metadata = SongUploadMetadata(title: "Title", artist: "Neuro", playlistID: nil)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStagingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A file of `size` bytes with a repeating, position-dependent pattern,
    /// so a dropped or reordered chunk changes the bytes.
    private func sourceFile(size: Int, name: String = "song.mp3") throws -> (URL, Data) {
        let bytes = Data((0..<size).map { index in UInt8(truncatingIfNeeded: index &* 31 &+ index >> 11) })
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private var outbox: URL {
        directory.appendingPathComponent("outbox", isDirectory: true)
    }

    @Test("The staged body is the preamble, the file's bytes, then the epilogue")
    func stagedBodyIsPreambleFileEpilogue() async throws {
        let (source, bytes) = try sourceFile(size: 3 * 1024 * 1024)
        let staged = try await UploadStaging.stage(source: source, metadata: metadata, directory: outbox)

        let expected = KaraokeAPIClient.multipartPreamble(
            boundary: staged.boundary,
            metadata: metadata,
            filename: "song.mp3",
            contentType: "audio/mpeg"
        ) + bytes + KaraokeAPIClient.multipartEpilogue(boundary: staged.boundary)
        let body = try Data(contentsOf: staged.fileURL)
        #expect(body == expected)
        #expect(staged.bodyBytes == Int64(expected.count))
        #expect(staged.sourceBytes == Int64(bytes.count))
        #expect(staged.filename == "song.mp3")
        #expect(staged.contentType == "audio/mpeg")
        #expect(staged.fileURL.deletingLastPathComponent().standardizedFileURL == outbox.standardizedFileURL)
    }

    @Test("Staging reads the file in chunks of at most the chunk size")
    func stagingKeepsMemoryFlat() async throws {
        let size = 3 * 1024 * 1024 + 17
        let (source, _) = try sourceFile(size: size)
        let reads = Mutex<[Int]>([])
        _ = try await UploadStaging.stage(
            source: source,
            metadata: metadata,
            directory: outbox,
            didReadChunk: { count in reads.withLock { $0.append(count) } }
        )
        let chunks = reads.withLock { $0 }
        #expect(chunks == [UploadStaging.chunkSize, UploadStaging.chunkSize, UploadStaging.chunkSize, 17])
        #expect(UploadStaging.chunkSize == 1024 * 1024)
    }

    @Test("A cancelled staging stops between chunks and leaves no file behind")
    func stagingHonoursCancellation() async throws {
        let (source, _) = try sourceFile(size: 64 * 1024)
        let reads = Mutex(0)
        let id = UUID()
        await #expect(throws: CancellationError.self) {
            try await UploadStaging.stage(
                source: source,
                metadata: metadata,
                directory: outbox,
                id: id,
                chunkSize: 4096,
                didReadChunk: { _ in
                    reads.withLock { $0 += 1 }
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            )
        }
        #expect(reads.withLock { $0 } == 1)
        #expect(!FileManager.default.fileExists(atPath: UploadStaging.fileURL(for: id, in: outbox).path))
    }

    @Test("A file that can't be read fails as unreadable")
    func unreadableSourceFails() async {
        let missing = directory.appendingPathComponent("missing.mp3")
        await #expect(throws: SongUploadFailure.fileUnreadable) {
            try await UploadStaging.stage(source: missing, metadata: metadata, directory: outbox)
        }
    }

    @Test("Staged files and their folder are excluded from backup")
    func stagedFileIsExcludedFromBackup() async throws {
        let (source, _) = try sourceFile(size: 1000)
        let staged = try await UploadStaging.stage(source: source, metadata: metadata, directory: outbox)
        let fileValues = try staged.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let folderValues = try outbox.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(fileValues.isExcludedFromBackup == true)
        #expect(folderValues.isExcludedFromBackup == true)
    }

    @Test("Discarding removes the staged file")
    func discardRemovesStagedFile() async throws {
        let (source, _) = try sourceFile(size: 1000)
        let staged = try await UploadStaging.stage(source: source, metadata: metadata, directory: outbox)
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
        UploadStaging.discard(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("The sweep removes only old files no pending upload needs")
    func sweepRemovesOnlyStaleUnreferencedFiles() throws {
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let now = Date()
        let old = now.addingTimeInterval(-8 * 24 * 60 * 60)
        func file(_ id: UUID, modified: Date) throws -> URL {
            let url = UploadStaging.fileURL(for: id, in: outbox)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return url
        }
        let staleID = UUID(), activeID = UUID(), freshID = UUID()
        let stale = try file(staleID, modified: old)
        let active = try file(activeID, modified: old)
        let fresh = try file(freshID, modified: now.addingTimeInterval(-60))
        let journal = outbox.appendingPathComponent("outbox.json")
        try Data("{}".utf8).write(to: journal)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: journal.path)

        UploadStaging.sweepStale(keeping: [activeID], directory: outbox, now: now)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }
}
