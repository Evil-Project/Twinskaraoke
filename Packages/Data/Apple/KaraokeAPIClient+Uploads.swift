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
    /// main API. The caller streams the body: `multipartPreamble`, the file's
    /// bytes, then `multipartEpilogue`.
    static func songUploadRequest(
        metadata: SongUploadMetadata,
        boundary: String,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let token = try signedInToken(readToken)
        guard var components = URLComponents(string: StorageHost.idk) else { throw APIError.invalidURL }
        components.path = uploadPath
        let queryItems = metadata.queryItems
        components.queryItems = queryItems.isEmpty ? nil : queryItems
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

    /// The opening of the body's only part, which carries the file in `File`.
    static func multipartPreamble(boundary: String, filename: String, contentType: String) -> Data {
        let safeName = sanitizedFilename(filename)
        let header = "--\(boundary)\r\n"
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

    /// Asks the server to download the linked audio into the user's uploads.
    /// Not retried: a repeat could add the song twice.
    static func importSongFromLink(_ link: SongLinkImport) async throws {
        do {
            _ = try await data(for: importSongFromLinkRequest(link))
        } catch {
            logFailure("Link import", error: error)
            throw error
        }
        await invalidateUploadedSongs()
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

    static func updateUploadedSong(id: String, edit: UploadedSongEdit) async throws {
        do {
            _ = try await data(for: updateUploadedSongRequest(id: id, edit: edit))
        } catch {
            logFailure("Upload edit", error: error)
            throw error
        }
        await invalidateUploadedSongs()
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

    static func deleteUploadedSong(id: String) async throws {
        do {
            _ = try await data(for: deleteUploadedSongRequest(id: id))
        } catch {
            logFailure("Upload delete", error: error)
            throw error
        }
        await invalidateUploadedSongs()
    }

    // MARK: - Caches

    /// Drops cached upload metadata and playlist details after the user's
    /// uploads change. Deleting an upload also removes it from every playlist
    /// that held it, so all cached playlists may be stale.
    static func invalidateUploadedSongs() async {
        await uploadedSongMetadataCache.invalidate()
        await playlistDetailCache.invalidateAll()
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
    /// request URL, and bodies may echo user data.
    private static func logFailure(_ action: String, error: Error) {
        let reason = switch error {
        case let APIError.httpStatus(status): "HTTP \(status)"
        case let urlError as URLError: "URLError \(urlError.code.rawValue)"
        case let failure as SongUploadFailure: "\(failure)"
        default: String(describing: type(of: error))
        }
        DebugLogger.log("\(action) failed: \(reason)", category: .network)
    }
}
