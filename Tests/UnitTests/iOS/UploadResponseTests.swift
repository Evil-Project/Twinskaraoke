import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

/// How the upload write calls (link import, edit, delete) read the server's
/// answers. Every response comes from a stub `send`; nothing reaches a server.
@Suite("Upload responses", .serialized)
struct UploadResponseTests {
    private static let token: () -> String? = { "test-token" }

    /// Answers each request with the next canned result and counts the calls.
    private nonisolated final class StubSend: Sendable {
        private let state: Mutex<(results: [Result<(Int, String), URLError>], calls: Int)>

        init(_ results: [Result<(Int, String), URLError>]) {
            state = Mutex((results, 0))
        }

        var callCount: Int {
            state.withLock { $0.calls }
        }

        var send: KaraokeAPIClient.UploadSend {
            { [self] request in
                let next = state.withLock { state in
                    state.calls += 1
                    return state.results.isEmpty ? .failure(URLError(.unknown)) : state.results.removeFirst()
                }
                let (status, body) = try next.get()
                let response = HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"),
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json; charset=utf-8", "Retry-After": "12"]
                )
                return (Data(body.utf8), response ?? URLResponse())
            }
        }
    }

    private nonisolated final class Counter: Sendable {
        private let count = Mutex(0)
        var value: Int {
            count.withLock { $0 }
        }

        func bump() {
            count.withLock { $0 += 1 }
        }
    }

    private static func song(_ id: String) -> Song {
        Song(
            id: id, title: id, duration: 60, absolutePath: nil, cloudflareID: nil, coverArt: nil,
            originalArtists: nil, coverArtists: nil, userUploaded: true
        )
    }

    private static func request() throws -> URLRequest {
        try KaraokeAPIClient.deleteUploadedSongRequest(id: "song-1", readToken: token)
    }

    private static func failure(of operation: () async throws -> some Any) async -> Error? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Server text reaches the caller

    @Test("A rejected link import throws the server's message")
    func linkImportKeepsServerMessage() async {
        let stub = StubSend([.success((
            400,
            #""Unsupported platform. Only YouTube, Bilibili and Discord attachments are supported.""#
        ))])
        let error = await Self.failure {
            try await KaraokeAPIClient.importSongFromLink(
                SongLinkImport(url: "https://youtu.be/abc", playlistID: nil),
                readToken: Self.token,
                send: stub.send
            )
        }
        let expected = UploadServerProblem(
            message: "Unsupported platform. Only YouTube, Bilibili and Discord attachments are supported.",
            fieldErrors: [:]
        )
        #expect(error as? SongUploadFailure == .server(status: 400, problem: expected))
    }

    @Test("A successful link import returns the server's answer")
    func linkImportReturnsResult() async throws {
        let stub = StubSend([.success((200, #"{"success":true,"songId":"s-9","title":"Clip"}"#))])
        let result = try await KaraokeAPIClient.importSongFromLink(
            SongLinkImport(url: "https://youtu.be/abc", playlistID: nil),
            readToken: Self.token,
            send: stub.send
        )
        #expect(result == SongLinkImportResult(success: true, songID: "s-9", title: "Clip"))

        let empty = StubSend([.success((200, ""))])
        let none = try await KaraokeAPIClient.importSongFromLink(
            SongLinkImport(url: "https://youtu.be/abc", playlistID: nil),
            readToken: Self.token,
            send: empty.send
        )
        #expect(none == nil)
    }

    @Test("Edit and delete failures carry the server's message and status")
    func editAndDeleteKeepServerMessage() async {
        let message = "Song not found or you do not have permission to update this song."
        let edit = StubSend([.success((400, "\"\(message)\""))])
        let editError = await Self.failure {
            try await KaraokeAPIClient.updateUploadedSong(
                id: "song-1",
                edit: UploadedSongEdit(title: "T", artist: "A"),
                readToken: Self.token,
                send: edit.send
            )
        }
        let problem = UploadServerProblem(message: message, fieldErrors: [:])
        #expect(editError as? SongUploadFailure == .server(status: 400, problem: problem))

        let delete = StubSend([.success((401, #""Attempted to perform an unauthorized operation.""#))])
        let deleteError = await Self.failure {
            try await KaraokeAPIClient.deleteUploadedSong(id: "song-1", readToken: Self.token, send: delete.send)
        }
        let unauthorized = UploadServerProblem(message: "Attempted to perform an unauthorized operation.", fieldErrors: [:])
        #expect(deleteError as? SongUploadFailure == .server(status: 401, problem: unauthorized))
    }

    @Test("Transport errors map to offline, timed out, interrupted and rate limited")
    func transportErrorsMapToFailures() async throws {
        let cases: [(Result<(Int, String), URLError>, SongUploadFailure)] = [
            (.failure(URLError(.notConnectedToInternet)), .offline),
            (.failure(URLError(.cannotFindHost)), .offline),
            (.failure(URLError(.timedOut)), .timedOut),
            (.failure(URLError(.networkConnectionLost)), .interrupted),
            (.success((429, "")), .rateLimited(retryAfter: 12)),
            (.success((500, #""An unexpected error occurred""#)), .server(
                status: 500,
                problem: UploadServerProblem(message: "An unexpected error occurred", fieldErrors: [:])
            )),
        ]
        for (result, expected) in cases {
            let stub = StubSend([result])
            let request = try Self.request()
            let error = await Self.failure {
                try await KaraokeAPIClient.sendUploadWrite(request, action: "Test", send: stub.send, invalidate: {})
            }
            #expect(error as? SongUploadFailure == expected, "\(result)")
        }
    }

    // MARK: - Delete is sent once

    @Test("A delete whose answer is lost is not sent again")
    func deleteIsNeverRetried() async {
        let stub = StubSend([.failure(URLError(.timedOut)), .success((400, #""Song not found""#))])
        let error = await Self.failure {
            try await KaraokeAPIClient.deleteUploadedSong(id: "song-1", readToken: Self.token, send: stub.send)
        }
        #expect(error as? SongUploadFailure == .timedOut)
        #expect(stub.callCount == 1)

        let failing = StubSend([.success((503, "")), .success((204, ""))])
        _ = await Self.failure {
            try await KaraokeAPIClient.deleteUploadedSong(id: "song-1", readToken: Self.token, send: failing.send)
        }
        #expect(failing.callCount == 1)
    }

    // MARK: - Cache invalidation

    @Test("Caches are dropped after a success or an ambiguous failure, not after a clean rejection")
    func invalidatesOnlyWhenServerMayHaveChanged() async throws {
        let cases: [(Result<(Int, String), URLError>, Bool)] = [
            (.success((204, "")), true),
            (.failure(URLError(.timedOut)), true),
            (.failure(URLError(.networkConnectionLost)), true),
            (.success((500, "")), true),
            (.success((400, #""Song not found""#)), false),
            (.success((401, "")), false),
            (.success((429, "")), false),
            (.failure(URLError(.notConnectedToInternet)), false),
        ]
        for (result, invalidates) in cases {
            let stub = StubSend([result])
            let counter = Counter()
            let request = try Self.request()
            _ = await Self.failure {
                try await KaraokeAPIClient.sendUploadWrite(request, action: "Test", send: stub.send) {
                    counter.bump()
                }
            }
            #expect(counter.value == (invalidates ? 1 : 0), "\(result)")
        }
    }

    @Test("Signed out, nothing is sent and nothing is invalidated")
    func signedOutSendsNothing() async {
        let stub = StubSend([.success((204, ""))])
        let error = await Self.failure {
            try await KaraokeAPIClient.deleteUploadedSong(id: "song-1", readToken: { nil }, send: stub.send)
        }
        #expect(error as? SongUploadFailure == .signedOut)
        #expect(stub.callCount == 0)
    }

    @Test("Invalidating uploads also drops cached favourites, which carry upload metadata")
    func invalidatingUploadsDropsFavourites() async throws {
        let first = Self.song("fav-old")
        let second = Self.song("fav-new")
        let cached = try await KaraokeAPIClient.favoriteSongsCache.value { [first] }
        #expect(cached.map(\.id) == ["fav-old"])

        await KaraokeAPIClient.invalidateUploadedSongs()

        let reloaded = try await KaraokeAPIClient.favoriteSongsCache.value { [second] }
        #expect(reloaded.map(\.id) == ["fav-new"])
        await KaraokeAPIClient.invalidateFavoriteSongs()
    }
}
