import Foundation
import Synchronization

/// An upload whose transfer was handed to the background session, kept on
/// disk so a relaunched app can match the session's tasks to it.
nonisolated struct PendingUpload: Codable, Sendable, Equatable, Identifiable {
    /// The staged body's id.
    var id: UUID
    /// The background session's task identifier, once a transfer started.
    var taskID: Int?
    var title: String
    var fileBytes: Int64
    var startedAt: Date
    /// The user's upload ids before this one started. The server's answer
    /// carries no id, so a new id in the list afterwards is this upload.
    var knownSongIDs: Set<String>
    // What a retry needs to send the staged body again.
    var bodyBytes: Int64
    var filename: String
    var contentType: String
    var boundary: String

    init(staged: StagedUpload, taskID: Int?, title: String, startedAt: Date, knownSongIDs: Set<String>) {
        id = staged.id
        self.taskID = taskID
        self.title = title
        fileBytes = staged.sourceBytes
        self.startedAt = startedAt
        self.knownSongIDs = knownSongIDs
        bodyBytes = staged.bodyBytes
        filename = staged.filename
        contentType = staged.contentType
        boundary = staged.boundary
    }

    /// The staged body this entry names, in `directory`.
    func staged(in directory: URL = UploadStaging.defaultDirectory) -> StagedUpload {
        StagedUpload(
            id: id,
            fileURL: UploadStaging.fileURL(for: id, in: directory),
            bodyBytes: bodyBytes,
            sourceBytes: fileBytes,
            filename: filename,
            contentType: contentType,
            boundary: boundary
        )
    }
}

/// The pending uploads, as a small versioned JSON file written atomically.
/// A file that can't be read, or has another version, counts as empty: the
/// worst case is an upload the app no longer tracks, whose staged body the
/// stale sweep removes later.
nonisolated final class UploadOutboxStore: Sendable {
    private struct Snapshot: Codable {
        var version: Int
        var uploads: [PendingUpload]
    }

    private enum Backing {
        case file(URL)
        case memory
    }

    static let version = 1
    private let backing: Backing
    /// Every read and write goes through the lock, so calls from different
    /// tasks never interleave a read-modify-write.
    private let state = Mutex<[PendingUpload]?>(nil)

    init(fileURL: URL) {
        backing = .file(fileURL)
    }

    private init(memory _: Void) {
        backing = .memory
        state.withLock { $0 = [] }
    }

    static var live: UploadOutboxStore {
        UploadOutboxStore(fileURL: UploadStaging.defaultDirectory.appendingPathComponent("outbox.json"))
    }

    static func inMemory() -> UploadOutboxStore {
        UploadOutboxStore(memory: ())
    }

    func entries() -> [PendingUpload] {
        state.withLock { cached in loaded(&cached) }
    }

    /// Adds `upload`, or replaces the entry with its id.
    func save(_ upload: PendingUpload) {
        update { uploads in
            if let index = uploads.firstIndex(where: { $0.id == upload.id }) {
                uploads[index] = upload
            } else {
                uploads.append(upload)
            }
        }
    }

    func remove(id: UUID) {
        update { $0.removeAll { $0.id == id } }
    }

    private func update(_ change: (inout [PendingUpload]) -> Void) {
        state.withLock { cached in
            var uploads = loaded(&cached)
            change(&uploads)
            cached = uploads
            write(uploads)
        }
    }

    private func loaded(_ cached: inout [PendingUpload]?) -> [PendingUpload] {
        if let cached { return cached }
        let uploads = read()
        cached = uploads
        return uploads
    }

    private func read() -> [PendingUpload] {
        guard case let .file(url) = backing else { return [] }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
            return snapshot.version == Self.version ? snapshot.uploads : []
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            DebugLogger.log("Upload outbox unreadable; starting empty", category: .network)
            return []
        }
    }

    private func write(_ uploads: [PendingUpload]) {
        guard case let .file(url) = backing else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(version: Self.version, uploads: uploads))
            try data.write(to: url, options: .atomic)
        } catch {
            DebugLogger.log("Upload outbox write failed: \(type(of: error))", category: .network)
        }
    }
}
