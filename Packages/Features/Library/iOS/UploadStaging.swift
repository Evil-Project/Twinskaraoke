import Foundation

/// A multipart upload body written to disk, ready for a background upload
/// task, which can only send a body from a file.
nonisolated struct StagedUpload: Sendable, Equatable {
    let id: UUID
    let fileURL: URL
    /// The whole body: metadata parts, file part header, the file, epilogue.
    let bodyBytes: Int64
    /// The source file's size, which the quota is checked against.
    let sourceBytes: Int64
    /// The name sent in the file part.
    let filename: String
    let contentType: String
    /// The multipart boundary the request's `Content-Type` must name.
    let boundary: String
}

/// Writes upload bodies into the outbox folder and cleans it up.
///
/// The folder is in Application Support, not Caches: the system may purge
/// Caches while a background upload still needs its file. It is excluded
/// from backup, since a staged body is only useful until it is sent.
nonisolated enum UploadStaging {
    static let chunkSize = 1 << 20
    static let fileExtension = "upload"
    static let defaultStaleAge: TimeInterval = 7 * 24 * 60 * 60

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UploadOutbox", isDirectory: true)
    }

    static func fileURL(for id: UUID, in directory: URL = defaultDirectory) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(fileExtension)
    }

    /// Copies `source` into a staged multipart body, `chunkSize` bytes at a
    /// time, so a large file is never held in memory. Runs off the main
    /// actor and stops between chunks when the task is cancelled, removing
    /// the partial file. `didReadChunk` sees each chunk's size, for tests.
    @concurrent
    static func stage(
        source: URL,
        metadata: SongUploadMetadata,
        filename: String? = nil,
        directory: URL = defaultDirectory,
        id: UUID = UUID(),
        chunkSize: Int = chunkSize,
        didReadChunk: @Sendable (Int) -> Void = { _ in }
    ) async throws -> StagedUpload {
        let name = filename ?? source.lastPathComponent
        let contentType = KaraokeAPIClient.uploadContentType(forFilename: name)
        let boundary = "Twinskaraoke-\(UUID().uuidString)"
        let destination = fileURL(for: id, in: directory)
        try prepare(directory)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw SongUploadFailure.fileUnreadable
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            let preamble = KaraokeAPIClient.multipartPreamble(
                boundary: boundary,
                metadata: metadata,
                filename: name,
                contentType: contentType
            )
            try output.write(contentsOf: preamble)
            let sourceBytes = try copy(source, to: output, chunkSize: chunkSize, didReadChunk: didReadChunk)
            let epilogue = KaraokeAPIClient.multipartEpilogue(boundary: boundary)
            try output.write(contentsOf: epilogue)
            try output.synchronize()
            try excludeFromBackup(destination)
            return StagedUpload(
                id: id,
                fileURL: destination,
                bodyBytes: Int64(preamble.count) + sourceBytes + Int64(epilogue.count),
                sourceBytes: sourceBytes,
                filename: name,
                contentType: contentType,
                boundary: boundary
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Holds the security scope of a picked file only while it is read.
    private static func copy(
        _ source: URL,
        to output: FileHandle,
        chunkSize: Int,
        didReadChunk: @Sendable (Int) -> Void
    ) throws -> Int64 {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: source)
        } catch {
            throw SongUploadFailure.fileUnreadable
        }
        defer { try? input.close() }
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                guard let read = try input.read(upToCount: chunkSize), !read.isEmpty else { break }
                chunk = read
            } catch {
                throw SongUploadFailure.fileUnreadable
            }
            didReadChunk(chunk.count)
            try output.write(contentsOf: chunk)
            total += Int64(chunk.count)
        }
        try Task.checkCancellation()
        return total
    }

    private static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Removes a staged body once its upload has ended for good.
    static func discard(_ staged: StagedUpload) {
        try? FileManager.default.removeItem(at: staged.fileURL)
    }

    /// Removes staged bodies older than `age` that no pending upload names,
    /// such as one left by an upload the app lost track of. Files in
    /// `keeping` are never removed, however old. Lists and reads the folder
    /// off the main actor.
    @concurrent
    static func sweepStale(
        olderThan age: TimeInterval = defaultStaleAge,
        keeping: Set<UUID>,
        directory: URL = defaultDirectory,
        now: Date = Date()
    ) async {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return }
        for file in files where file.pathExtension == fileExtension {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  !keeping.contains(id),
                  let modified = try? file.resourceValues(forKeys: Set(keys)).contentModificationDate,
                  now.timeIntervalSince(modified) > age
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
