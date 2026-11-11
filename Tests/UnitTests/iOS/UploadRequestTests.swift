import Foundation
import Testing
@testable import Twinskaraoke

/// Request shapes for the song-upload endpoints. Every test builds a request
/// and inspects it; none sends one.
@Suite("Upload requests")
struct UploadRequestTests {
    private static let token: () -> String? = { "test-token" }

    private static func queryItems(of request: URLRequest) -> [URLQueryItem] {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return [] }
        return components.queryItems ?? []
    }

    private static func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static func limits(
        maxSongs: Int = 50,
        currentSongCount: Int = 10,
        maxStorageBytes: Int64 = 1000,
        usedStorageBytes: Int64 = 400
    ) -> UploadLimits {
        UploadLimits(
            maxSongs: maxSongs,
            maxStorageBytes: maxStorageBytes,
            usedStorageBytes: usedStorageBytes,
            currentSongCount: currentSongCount,
            currentPlaylistCount: 0,
            playlistLimit: 10,
            songPerPlaylistLimit: 100
        )
    }

    // MARK: - Upload

    @Test("The upload goes to the upload host as an authorised multipart POST")
    func uploadRequestTargetsUploadHost() throws {
        let request = try KaraokeAPIClient.songUploadRequest(
            metadata: SongUploadMetadata(title: "Title", artist: "Artist", playlistID: nil),
            boundary: "BOUNDARY",
            readToken: Self.token
        )
        let url = try #require(request.url)
        let expectedHost = try #require(URL(string: StorageHost.idk)?.host())
        #expect(url.host() == expectedHost)
        #expect(url.path() == "/api/user/song/upload")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=BOUNDARY")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.timeoutInterval == 120)
    }

    @Test("Empty or blank metadata is left out so the server reads the file's tags")
    func uploadRequestOmitsEmptyMetadata() throws {
        let request = try KaraokeAPIClient.songUploadRequest(
            metadata: SongUploadMetadata(title: "", artist: "  \n", playlistID: nil),
            boundary: "B",
            readToken: Self.token
        )
        #expect(Self.queryItems(of: request).isEmpty)
        #expect(request.url?.query() == nil)
    }

    @Test("Metadata uses the server's parameter names, capitalised")
    func uploadRequestKeepsSpecCasing() throws {
        let request = try KaraokeAPIClient.songUploadRequest(
            metadata: SongUploadMetadata(title: " Song ", artist: "Neuro", playlistID: "pl-1"),
            boundary: "B",
            readToken: Self.token
        )
        let items = Self.queryItems(of: request)
        #expect(items.map(\.name).sorted() == ["Artist", "PlaylistId", "Title"])
        #expect(items.first { $0.name == "Title" }?.value == "Song")
        #expect(items.first { $0.name == "Artist" }?.value == "Neuro")
        #expect(items.first { $0.name == "PlaylistId" }?.value == "pl-1")
    }

    @Test("Without a token the upload request is refused as signed out")
    func uploadRequestRequiresToken() {
        #expect(throws: SongUploadFailure.signedOut) {
            try KaraokeAPIClient.songUploadRequest(
                metadata: SongUploadMetadata(title: "", artist: "", playlistID: nil),
                boundary: "B",
                readToken: { nil }
            )
        }
    }

    @Test("The upload never sends a guest id")
    func uploadRequestSendsNoGuestID() throws {
        let request = try KaraokeAPIClient.songUploadRequest(
            metadata: SongUploadMetadata(title: "", artist: "", playlistID: nil),
            boundary: "B",
            readToken: Self.token
        )
        #expect(request.value(forHTTPHeaderField: "x-guest-id") == nil)
    }

    // MARK: - Multipart

    @Test("The multipart part carries the file under the server's field name")
    func multipartPreambleNamesFileField() throws {
        let preamble = KaraokeAPIClient.multipartPreamble(
            boundary: "B",
            filename: "Song.mp3",
            contentType: "audio/mpeg"
        )
        let text = try #require(String(data: preamble, encoding: .utf8))
        #expect(text.hasPrefix("--B\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"File\"; filename=\"Song.mp3\"\r\n"))
        #expect(text.contains("Content-Type: audio/mpeg\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test("The filename loses quotes, backslashes and line breaks but keeps UTF-8")
    func multipartFilenameStripsQuotesAndNewlines() throws {
        let preamble = KaraokeAPIClient.multipartPreamble(
            boundary: "B",
            filename: "ネ\"uro\r\nX-Evil: 1\\.mp3",
            contentType: "audio/mpeg"
        )
        let text = try #require(String(data: preamble, encoding: .utf8))
        #expect(text.contains("filename=\"ネuroX-Evil: 1.mp3\""))
        #expect(!text.contains("\r\nX-Evil"))
    }

    @Test("Every multipart line ends in CRLF and the epilogue closes the boundary")
    func multipartUsesCRLF() throws {
        let preamble = try #require(String(
            data: KaraokeAPIClient.multipartPreamble(boundary: "B", filename: "a.m4a", contentType: "audio/mp4"),
            encoding: .utf8
        ))
        let epilogue = try #require(String(data: KaraokeAPIClient.multipartEpilogue(boundary: "B"), encoding: .utf8))
        let bareLineFeeds = (preamble + epilogue).replacingOccurrences(of: "\r\n", with: "").contains("\n")
        #expect(!bareLineFeeds)
        #expect(epilogue == "\r\n--B--\r\n")
        #expect(KaraokeAPIClient.uploadContentType(forFilename: "track.mp3") == "audio/mpeg")
        #expect(KaraokeAPIClient.uploadContentType(forFilename: "no-extension") == "application/octet-stream")
    }

    // MARK: - Link import

    @Test("A link import is a POST with the server's JSON field names")
    func linkImportRequestIsPostWithSpecJSON() throws {
        let request = try KaraokeAPIClient.importSongFromLinkRequest(
            SongLinkImport(url: "https://youtu.be/abc", playlistID: "pl-2"),
            readToken: Self.token
        )
        let url = try #require(request.url)
        let expectedHost = try #require(URL(string: StorageHost.api)?.host())
        #expect(url.host() == expectedHost)
        #expect(url.path() == "/api/user/song/download-from-url")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "x-guest-id") == nil)
        #expect(request.timeoutInterval >= 120)
        let body = try Self.jsonBody(of: request)
        #expect(Set(body.keys) == ["url", "playlistId"])
        #expect(body["url"] as? String == "https://youtu.be/abc")
        #expect(body["playlistId"] as? String == "pl-2")

        let withoutPlaylist = try KaraokeAPIClient.importSongFromLinkRequest(
            SongLinkImport(url: "https://youtu.be/abc", playlistID: nil),
            readToken: Self.token
        )
        #expect(try Set(Self.jsonBody(of: withoutPlaylist).keys) == ["url"])
        #expect(throws: SongUploadFailure.signedOut) {
            try KaraokeAPIClient.importSongFromLinkRequest(
                SongLinkImport(url: "https://youtu.be/abc", playlistID: nil),
                readToken: { nil }
            )
        }
    }

    @Test("Only http(s) YouTube and Bilibili links are accepted")
    func linkImportAcceptsOnlyYouTubeAndBilibili() {
        let accepted = [
            "https://www.youtube.com/watch?v=abc",
            "  https://youtube.com/playlist?list=PL1\n",
            "https://m.youtube.com/watch?v=abc",
            "https://music.youtube.com/watch?v=abc",
            "http://youtu.be/abc",
            "https://WWW.YouTube.com/watch?v=abc",
            "https://www.bilibili.com/video/BV1xx411c7mD",
            "https://bilibili.com/video/BV1xx411c7mD",
            "https://m.bilibili.com/video/BV1xx411c7mD",
            "https://b23.tv/abc123",
        ]
        for link in accepted {
            #expect(SongLinkImport.supportedLink(link) != nil, "\(link)")
        }
        #expect(SongLinkImport.supportedLink("  https://youtu.be/abc ")?.absoluteString == "https://youtu.be/abc")

        let rejected = [
            "http://evil.example/?u=youtube.com",
            "https://youtube.com.evil.example/watch?v=abc",
            "https://notyoutube.com/watch?v=abc",
            "https://youtube.com@evil.example/watch",
            "ftp://youtube.com/watch?v=abc",
            "youtube.com/watch?v=abc",
            "javascript:alert(1)",
            "https://soundcloud.com/a/b",
            "not a url at all",
            "",
        ]
        for link in rejected {
            #expect(SongLinkImport.supportedLink(link) == nil, "\(link)")
        }
    }

    // MARK: - Edit and delete

    @Test("An edit is a POST to the song with title and artist only")
    func updateRequestIsPostWithSpecJSON() throws {
        let request = try KaraokeAPIClient.updateUploadedSongRequest(
            id: "song-1",
            edit: UploadedSongEdit(title: "New", artist: "Evil"),
            readToken: Self.token
        )
        #expect(request.url?.path() == "/api/user/song/song-1")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let body = try Self.jsonBody(of: request)
        #expect(Set(body.keys) == ["title", "artist"])
        #expect(body["title"] as? String == "New")
        #expect(body["artist"] as? String == "Evil")
    }

    @Test("The song id is percent-encoded as one path segment")
    func updateRequestPercentEncodesID() throws {
        let request = try KaraokeAPIClient.updateUploadedSongRequest(
            id: "a/b?c",
            edit: UploadedSongEdit(title: "T", artist: "A"),
            readToken: Self.token
        )
        let url = try #require(request.url)
        #expect(url.path(percentEncoded: true) == "/api/user/song/a%2Fb%3Fc")
        #expect(url.query() == nil)
        #expect(throws: (any Error).self) {
            try KaraokeAPIClient.updateUploadedSongRequest(
                id: "..",
                edit: UploadedSongEdit(title: "T", artist: "A"),
                readToken: Self.token
            )
        }
    }

    @Test("Deleting a song uses DELETE on the song's path")
    func deleteRequestUsesDelete() throws {
        let request = try KaraokeAPIClient.deleteUploadedSongRequest(id: "song-1", readToken: Self.token)
        #expect(request.url?.path() == "/api/user/song/song-1")
        #expect(request.httpMethod == "DELETE")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(throws: SongUploadFailure.signedOut) {
            try KaraokeAPIClient.deleteUploadedSongRequest(id: "song-1", readToken: { nil })
        }
    }

    // MARK: - Server problems

    @Test("A problem-details body yields its message and field errors")
    func problemDetailsParsesFieldErrors() throws {
        let body = Data("""
            {"type":"x","title":"One or more validation errors occurred.","status":400,
             "errors":{"Title":["Too long."],"File":["Required.","Bad type."]}}
            """.utf8)
        let problem = try #require(UploadServerProblem.parse(
            data: body,
            contentType: "application/problem+json; charset=utf-8"
        ))
        #expect(problem.message == "One or more validation errors occurred.")
        #expect(problem.fieldErrors == ["Title": ["Too long."], "File": ["Required.", "Bad type."]])

        let detailed = UploadServerProblem.parse(
            data: Data(#"{"title":"Bad Request","detail":"Storage quota exceeded"}"#.utf8),
            contentType: "application/json"
        )
        #expect(detailed == UploadServerProblem(message: "Storage quota exceeded", fieldErrors: [:]))
    }

    @Test("A plain-text body becomes one line of at most 300 characters")
    func plainTextProblemIsTruncated() throws {
        let long = "Upload failed:\n  " + String(repeating: "x", count: 500)
        let problem = try #require(UploadServerProblem.parse(
            data: Data(long.utf8),
            contentType: "text/plain; charset=utf-8"
        ))
        let message = try #require(problem.message)
        #expect(message.count == 300)
        #expect(!message.contains("\n"))
        #expect(message.hasPrefix("Upload failed: xxx"))
        #expect(problem.fieldErrors.isEmpty)
    }

    @Test("Unknown, empty or malformed bodies parse to nil")
    func unknownProblemBodyParsesToNil() {
        #expect(UploadServerProblem.parse(data: Data("<html>502</html>".utf8), contentType: "text/html") == nil)
        #expect(UploadServerProblem.parse(data: Data("oops".utf8), contentType: nil) == nil)
        #expect(UploadServerProblem.parse(data: Data("{not json".utf8), contentType: "application/problem+json") == nil)
        #expect(UploadServerProblem.parse(data: Data("[1,2]".utf8), contentType: "application/json") == nil)
        #expect(UploadServerProblem.parse(data: Data("{}".utf8), contentType: "application/json") == nil)
        #expect(UploadServerProblem.parse(data: Data(" \n ".utf8), contentType: "text/plain") == nil)
    }

    // MARK: - Limits

    @Test("A file larger than the remaining storage is blocked")
    func limitsBlockFileOverRemainingStorage() {
        let limits = Self.limits(maxStorageBytes: 1000, usedStorageBytes: 400)
        #expect(limits.remainingBytes == 600)
        #expect(limits.blocking(fileSize: 601) == .quotaStorage(remaining: 600, needed: 601))

        let overUsed = Self.limits(maxStorageBytes: 1000, usedStorageBytes: 1200)
        #expect(overUsed.remainingBytes == 0)
        #expect(overUsed.blocking(fileSize: 1) == .quotaStorage(remaining: 0, needed: 1))
    }

    @Test("Reaching the song limit blocks before storage is checked")
    func limitsBlockWhenSongCountReached() {
        let limits = Self.limits(maxSongs: 10, currentSongCount: 10, maxStorageBytes: 100, usedStorageBytes: 100)
        #expect(limits.remainingSongs == 0)
        #expect(limits.blocking(fileSize: 5000) == .quotaSongs(max: 10))
        #expect(Self.limits(maxSongs: 10, currentSongCount: 12).remainingSongs == 0)
    }

    @Test("A file that fits is not blocked")
    func limitsAllowFileThatFits() {
        let limits = Self.limits(maxSongs: 50, currentSongCount: 49, maxStorageBytes: 1000, usedStorageBytes: 400)
        #expect(limits.remainingSongs == 1)
        #expect(limits.blocking(fileSize: 600) == nil)
        #expect(limits.blocking(fileSize: 0) == nil)
    }
}
