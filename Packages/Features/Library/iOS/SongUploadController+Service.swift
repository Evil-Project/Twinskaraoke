import Foundation

extension SongUploadController {
    /// Everything the controller reaches outside itself, replaced in tests.
    struct Service {
        var limits: @MainActor () async throws -> UploadLimits
        /// The ids of the user's uploads, to tell which song an upload added.
        var uploadedSongIDs: @MainActor () async throws -> Set<String>
        /// The upload request for a staged body, with the current token.
        var makeUploadRequest: @MainActor (_ staged: StagedUpload) throws -> URLRequest
        var importLink: @MainActor (_ link: SongLinkImport) async throws -> SongLinkImportResult?
        var transport: UploadTransport
        var outbox: UploadOutboxStore
        var stage: @MainActor (_ source: URL, _ metadata: SongUploadMetadata) async throws -> StagedUpload
        var discard: @MainActor (_ staged: StagedUpload) -> Void
        /// The size of a picked file, or `nil` when it can't be read.
        var fileSize: @MainActor (_ source: URL) -> Int64?
        var invalidateUploads: @MainActor () async -> Void
        /// Removes old staged bodies that none of `keeping` names.
        var sweepStaged: @MainActor (_ keeping: Set<UUID>) -> Void
        /// Who is signed in ("guest" when signed out), or `nil` when the
        /// Keychain can't tell. Read from storage, as the video resume store
        /// does; nothing here changes the session.
        var currentAccount: @MainActor () -> String?

        static var live: Service {
            Service(
                limits: { try await KaraokeAPIClient.uploadLimits() },
                uploadedSongIDs: { try await Set(KaraokeAPIClient.uploadedSongs().map(\.id)) },
                makeUploadRequest: { staged in
                    try KaraokeAPIClient.songUploadRequest(boundary: staged.boundary)
                },
                importLink: { link in try await KaraokeAPIClient.importSongFromLink(link) },
                transport: .live,
                outbox: .live,
                stage: { source, metadata in try await UploadStaging.stage(source: source, metadata: metadata) },
                discard: { staged in UploadStaging.discard(staged) },
                fileSize: { source in
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    return (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                },
                invalidateUploads: { await KaraokeAPIClient.invalidateUploadedSongs() },
                sweepStaged: { keeping in UploadStaging.sweepStale(keeping: keeping) },
                currentAccount: { VideoResumeStore.accountIdentity(for: AuthManager.persistedDescriptor()) }
            )
        }

        /// No network and no files, for UI tests launched with `-UITestMode`:
        /// a file upload reports half, then all of its body sent, then 200;
        /// a link import returns a title after three seconds, long enough for a
        /// UI test to see it running.
        static var uiTestFixture: Service {
            let transport = UploadTransport.uiTestFixture
            return Service(
                limits: {
                    UploadLimits(
                        maxSongs: 50,
                        maxStorageBytes: 500_000_000,
                        usedStorageBytes: 0,
                        currentSongCount: 0,
                        currentPlaylistCount: 0,
                        playlistLimit: 10,
                        songPerPlaylistLimit: 100
                    )
                },
                uploadedSongIDs: { [] },
                makeUploadRequest: { staged in
                    var request = URLRequest(url: URL(fileURLWithPath: "/ui-test-upload"))
                    request.httpMethod = "POST"
                    request.setValue(staged.boundary, forHTTPHeaderField: "X-UI-Test-Boundary")
                    return request
                },
                importLink: { _ in
                    try await Task.sleep(for: .seconds(3))
                    return SongLinkImportResult(success: true, songID: "ui-test-link", title: "UI Test Link Song")
                },
                transport: transport,
                outbox: .inMemory(),
                stage: { source, _ in
                    let id = UUID()
                    return StagedUpload(
                        id: id,
                        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString),
                        bodyBytes: 1000,
                        sourceBytes: 1000,
                        filename: source.lastPathComponent,
                        contentType: KaraokeAPIClient.uploadContentType(forFilename: source.lastPathComponent),
                        boundary: "ui-test"
                    )
                },
                discard: { _ in },
                fileSize: { _ in 1000 },
                invalidateUploads: {},
                sweepStaged: { _ in },
                currentAccount: { "ui-test" }
            )
        }
    }
}

nonisolated extension UploadTransport {
    /// Reports each started upload as half sent, fully sent, then answered
    /// with an empty 200.
    static var uiTestFixture: UploadTransport {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        return UploadTransport(
            start: { _, _ in
                let taskID = Int.random(in: 1...Int.max)
                Task {
                    for fraction in [0.5, 1.0] {
                        try? await Task.sleep(for: .milliseconds(300))
                        continuation.yield(.progress(taskID: taskID, fraction: fraction))
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                    continuation.yield(.finished(taskID: taskID, status: 200, body: Data(), contentType: nil, retryAfter: nil))
                }
                return taskID
            },
            cancel: { taskID in continuation.yield(.failed(taskID: taskID, .cancelled)) },
            activeTaskIDs: { [] },
            events: { stream },
            acknowledge: { _ in },
            handleBackgroundEvents: {}
        )
    }
}
