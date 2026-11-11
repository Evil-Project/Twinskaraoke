import Foundation
import UniformTypeIdentifiers

/// The user's own uploads: adding a song from a file or a video link, editing
/// its title and artist, and deleting it. Every call needs a signed-in user.
nonisolated extension KaraokeAPIClient {
    private static let uploadPath = "/api/user/song/upload"
    private static let linkImportPath = "/api/user/song/download-from-url"

    /// The server downloads and converts the linked audio before it answers,
    /// which can take minutes for a long video or a playlist.
    private static let linkImportTimeout: TimeInterval = 600

    // MARK: - File upload

    /// The multipart POST for one file, on the upload host rather than the
    /// main API. The caller streams the body: `multipartPreamble` (the
    /// metadata fields and the file part's header), the file's bytes, then
    /// `multipartEpilogue`. The URL carries no metadata.
    static func songUploadRequest(
        boundary: String,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let token = try signedInToken(readToken)
        guard var components = URLComponents(string: StorageHost.upload) else { throw APIError.invalidURL }
        components.path = uploadPath
        guard let url = components.url else { throw APIError.invalidURL }
        // Built here rather than with `request(path:)`: the host differs, and
        // an upload must never fall back to a guest identity.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// The body up to the file's bytes: one part per metadata field, then
    /// the header of the part that carries the file in `File`.
    static func multipartPreamble(
        boundary: String,
        metadata: SongUploadMetadata,
        filename: String,
        contentType: String
    ) -> Data {
        let safeName = sanitizedFilename(filename)
        let fields = metadata.formFields.map { field in
            "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(field.name)\"\r\n"
                + "\r\n"
                + "\(field.value)\r\n"
        }
        let header = fields.joined() + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"File\"; filename=\"\(safeName)\"\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "\r\n"
        return Data(header.utf8)
    }

    /// Ends the file's part and the body.
    static func multipartEpilogue(boundary: String) -> Data {
        Data("\r\n--\(boundary)--\r\n".utf8)
    }

    /// The MIME type for a file's extension, or a generic binary type.
    static func uploadContentType(forFilename filename: String) -> String {
        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty else { return "application/octet-stream" }
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Drops the characters that could end the quoted filename or start a new
    /// header line. Other characters, including non-ASCII ones, are kept.
    private static func sanitizedFilename(_ filename: String) -> String {
        let cleaned = String(filename.unicodeScalars.filter { !"\"\\\r\n".unicodeScalars.contains($0) })
        return cleaned.isEmpty ? "upload" : cleaned
    }

    // MARK: - Link import

    static func importSongFromLinkRequest(
        _ link: SongLinkImport,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let token = try signedInToken(readToken)
        var request = try request(path: linkImportPath, readToken: { token })
        try setJSONBody(link, on: &request, method: "POST")
        request.timeoutInterval = linkImportTimeout
        return request
    }

    /// Asks the server to download the linked audio into the user's uploads
    /// and returns its answer, or `nil` when the body was empty or unreadable.
    /// Not retried: a repeat could add the song twice.
    @discardableResult
    static func importSongFromLink(
        _ link: SongLinkImport,
        readToken: () throws -> String? = CredentialStore.requestToken,
        send: UploadSend = sendThroughSharedSession
    ) async throws -> SongLinkImportResult? {
        let request = try importSongFromLinkRequest(link, readToken: readToken)
        let data = try await sendUploadWrite(request, action: "Link import", send: send)
        return SongLinkImportResult.decode(from: data)
    }

    // MARK: - Edit and delete

    static func updateUploadedSongRequest(
        id: String,
        edit: UploadedSongEdit,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let token = try signedInToken(readToken)
        var request = try request(pathSegments: ["api", "user", "song", id], readToken: { token })
        try setJSONBody(edit, on: &request, method: "POST")
        return request
    }

    static func updateUploadedSong(
        id: String,
        edit: UploadedSongEdit,
        readToken: () throws -> String? = CredentialStore.requestToken,
        send: UploadSend = sendThroughSharedSession
    ) async throws {
        let request = try updateUploadedSongRequest(id: id, edit: edit, readToken: readToken)
        _ = try await sendUploadWrite(request, action: "Upload edit", send: send)
    }

    static func deleteUploadedSongRequest(
        id: String,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let token = try signedInToken(readToken)
        var request = try request(pathSegments: ["api", "user", "song", id], readToken: { token })
        request.httpMethod = "DELETE"
        request.setValue(nil, forHTTPHeaderField: "x-guest-id")
        return request
    }

    /// Sent once: the server answers a repeated delete with 400, so a resend
    /// after a lost answer would report a successful delete as failed.
    static func deleteUploadedSong(
        id: String,
        readToken: () throws -> String? = CredentialStore.requestToken,
        send: UploadSend = sendThroughSharedSession
    ) async throws {
        let request = try deleteUploadedSongRequest(id: id, readToken: readToken)
        _ = try await sendUploadWrite(request, action: "Upload delete", send: send)
    }

    // MARK: - Limits

    static func uploadLimitsRequest(readToken: () throws -> String? = CredentialStore.requestToken) throws -> URLRequest {
        let token = try signedInToken(readToken)
        var request = try request(path: "/api/user/upload-limits", readToken: { token })
        request.httpMethod = "GET"
        request.setValue(nil, forHTTPHeaderField: "x-guest-id")
        return request
    }

    /// The user's song and storage quota. A read, so it goes through the
    /// shared path with its retries and session-expiry handling.
    static func uploadLimits() async throws -> UploadLimits {
        let data = try await data(for: uploadLimitsRequest())
        return try JSONDecoder().decode(UploadLimits.self, from: data)
    }

    // MARK: - Sending writes

    typealias UploadSend = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let sendThroughSharedSession: UploadSend = { request in
        try await URLSession.shared.data(for: request)
    }

    /// Sends an upload write once, without the shared path's retries, and
    /// turns a failure into a `SongUploadFailure` that keeps the server's
    /// message. The upload caches are dropped unless the failure shows the
    /// server didn't change anything: a write that may have landed must not
    /// leave stale caches behind.
    static func sendUploadWrite(
        _ request: URLRequest,
        action: String,
        send: UploadSend,
        invalidate: @Sendable () async -> Void = { await invalidateUploadedSongs() }
    ) async throws -> Data {
        do {
            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else { throw SongUploadFailure.unknown }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { reportSessionExpiryIfCurrent(request) }
                throw failure(status: http.statusCode, data: data, response: http)
            }
            await invalidate()
            return data
        } catch {
            let failure = uploadFailure(for: error)
            logFailure(action, error: failure ?? error)
            if mayHaveChangedServer(failure) { await invalidate() }
            throw failure ?? error
        }
    }

    private static func failure(status: Int, data: Data, response: HTTPURLResponse) -> SongUploadFailure {
        if status == 429 {
            return .rateLimited(retryAfter: retryAfterSeconds(response.value(forHTTPHeaderField: "Retry-After")))
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        return .server(status: status, problem: UploadServerProblem.parse(data: data, contentType: contentType))
    }

    /// `Retry-After` in seconds, capped at five minutes. An HTTP date is
    /// ignored; the caller then picks its own delay.
    static func retryAfterSeconds(_ value: String?) -> TimeInterval? {
        guard let value, let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds >= 0
        else { return nil }
        return min(seconds, 300)
    }

    /// The failure for a thrown error; `nil` for a cancellation, which is
    /// passed on as it is.
    private static func uploadFailure(for error: Error) -> SongUploadFailure? {
        switch error {
        case let failure as SongUploadFailure:
            failure
        case let urlError as URLError:
            switch urlError.code {
            case .cancelled: nil
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                .offline
            case .timedOut: .timedOut
            case .networkConnectionLost: .interrupted
            default: .unknown
            }
        default:
            nil
        }
    }

    /// False only when the request can't have changed anything: it was never
    /// sent (offline, signed out) or the server refused it with a 4xx.
    private static func mayHaveChangedServer(_ failure: SongUploadFailure?) -> Bool {
        switch failure {
        case .signedOut, .offline, .rateLimited, .quotaSongs, .quotaStorage, .fileUnreadable:
            false
        case let .server(status, _):
            !(400..<500).contains(status)
        case .timedOut, .interrupted, .unknown, nil:
            true
        }
    }

    /// The same session-expiry signal the shared path sends: only when the
    /// rejected token is still the current one, so a late answer for an old
    /// session can't sign out a new one.
    private static func reportSessionExpiryIfCurrent(_ request: URLRequest) {
        guard let current = CredentialStore.token,
              request.value(forHTTPHeaderField: "Authorization") == "Bearer \(current)"
        else { return }
        NotificationCenter.default.post(name: .karaokeSessionExpired, object: nil, userInfo: ["requestToken": current])
    }

    // MARK: - Caches

    /// Drops cached upload metadata, playlist details and favourites after
    /// the user's uploads change. Deleting an upload also removes it from
    /// every playlist that held it, so all cached playlists may be stale, and
    /// cached favourites carry upload titles and artists.
    static func invalidateUploadedSongs() async {
        await uploadedSongMetadataCache.invalidate()
        await playlistDetailCache.invalidateAll()
        await favoriteSongsCache.invalidate()
    }

    // MARK: - Helpers

    private static func signedInToken(_ readToken: () throws -> String?) throws -> String {
        guard let token = try readToken(), !token.isEmpty else { throw SongUploadFailure.signedOut }
        return token
    }

    /// The shared builders add a guest id whenever the credential store reads
    /// as signed out; these calls always carry a token, so it is removed.
    private static func setJSONBody(_ body: some Encodable, on request: inout URLRequest, method: String) throws {
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(nil, forHTTPHeaderField: "x-guest-id")
    }

    /// Logs the status or error code only: URLError descriptions include the
    /// request URL, and server messages may echo user data.
    private static func logFailure(_ action: String, error: Error) {
        let reason = switch error {
        case let APIError.httpStatus(status): "HTTP \(status)"
        case let urlError as URLError: "URLError \(urlError.code.rawValue)"
        case let SongUploadFailure.server(status, _): "HTTP \(status)"
        case let failure as SongUploadFailure: "\(failure)"
        default: String(describing: type(of: error))
        }
        DebugLogger.log("\(action) failed: \(reason)", category: .network)
    }
}
