import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Architecture compatibility")
struct ArchitectureRegressionTests {
    @Test("The extracted transport rejects error bodies before decoding")
    func httpStatusValidation() async throws {
        let url = try #require(URL(string: "https://example.com/profile"))
        let request = URLRequest(url: url)
        do {
            _ = try await HTTPTransport.data(for: request, allowsRetry: false, send: { _ in
                (Data(#"{"profile":{}}"#.utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }, readToken: { nil })
            Issue.record("An error body was accepted as successful data")
        } catch HTTPTransport.APIError.httpStatus(503) {
        }
    }

    @Test("A late unauthorized reply cannot expire a newer account")
    func staleUnauthorizedReply() async throws {
        let url = try #require(URL(string: "https://example.com/profile"))
        let expired = "expired-" + UUID().uuidString
        var request = URLRequest(url: url)
        request.setValue("Bearer " + expired, forHTTPHeaderField: "Authorization")
        let notifications = ExpirationRecorder()
        let observer = NotificationCenter.default.addObserver(forName: .karaokeSessionExpired,
            object: nil, queue: nil) { note in
            if note.userInfo?["requestToken"] as? String == expired { notifications.record() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        do {
            _ = try await HTTPTransport.data(for: request, allowsRetry: false, send: { _ in
                (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }, readToken: { "new-account" })
            Issue.record("Expected unauthorized response")
        } catch HTTPTransport.APIError.httpStatus(401) {
        }
        #expect(notifications.count == 0)
        do {
            _ = try await HTTPTransport.data(for: request, allowsRetry: false, send: { _ in
                (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }, readToken: { expired })
            Issue.record("Expected unauthorized response")
        } catch HTTPTransport.APIError.httpStatus(401) {
        }
        #expect(notifications.count == 1)
    }

    @Test("Playlist creation preserves wire field names and omitted descriptions")
    func playlistRequestContract() throws {
        let request = try UserPlaylistRepository.createRequest(name: "Mix", description: "", isPublic: true, readToken: { "token" })
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/playlist/save")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(body["Name"] as? String == "Mix")
        #expect(body["IsPublic"] as? Bool == true)
        #expect(body["IsSetList"] as? Bool == false)
        #expect(body["Description"] == nil)
    }

    @Test("Removing an absent playlist song succeeds, other HTTP failures propagate")
    func playlistRemovalContract() async throws {
        try await UserPlaylistRepository.removeSong("song", from: "playlist", execute: { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/playlist/playlist/song/song")
            throw KaraokeAPIClient.APIError.httpStatus(404)
        }, readToken: { nil })
        do {
            try await UserPlaylistRepository.removeSong("song", from: "playlist", execute: { _ in
                throw KaraokeAPIClient.APIError.httpStatus(403)
            }, readToken: { nil })
            Issue.record("A forbidden mutation was treated as successful")
        } catch KaraokeAPIClient.APIError.httpStatus(403) {
        }
    }

    @Test("Shared auth parsing preserves claim names and the RFC 7636 challenge")
    func authenticationContract() throws {
        let claims = [
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier": "user",
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name": "name",
            "urn:discord:avatar": "",
        ]
        let encoded = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let parsed = AuthenticationCodec.claims("header." + encoded + ".signature")
        #expect(parsed?.id == "user")
        #expect(parsed?.username == "name")
        #expect(parsed?.avatar == nil)
        #expect(AuthenticationCodec.claims("invalid") == nil)
        #expect(AuthenticationCodec.makeChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @MainActor
    @Test("A bound watch route receives playback commands without starting phone audio")
    func companionRoutingContract() {
        let player = AudioPlayerManager.shared
        let previous = player.companionRouter
        let route = RecordingCompanionRoute()
        player.companionRouter = route
        defer { player.companionRouter = previous }
        let previousSong = player.currentSong
        let song = UITestFixtures.song(id: "routed-song", title: "Routed", artist: "Artist")
        player.play(song: song, context: [song])
        #expect(route.action == .play)
        #expect(route.song?.id == song.id)
        #expect(route.queue?.map(\.id) == [song.id])
        #expect(player.currentSong == previousSong)
        #expect(player.routeIcon == "applewatch")
    }

    @MainActor
    @Test("Playback saves coalesce and releasing their owner cancels pending work")
    func persistenceLifetime() async {
        var callbacks: [Int] = []
        var persistence: PlaybackSessionPersistence? = PlaybackSessionPersistence()
        persistence?.schedule(periodic: false) { callbacks.append(1) }
        persistence?.schedule(periodic: false) { callbacks.append(2) }
        for _ in 0..<20 { await Task.yield() }
        #expect(callbacks == [2])
        persistence?.schedule(periodic: false) { callbacks.append(3) }
        persistence = nil
        for _ in 0..<20 { await Task.yield() }
        #expect(callbacks == [2])
    }
}

private nonisolated final class ExpirationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func record() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
private final class RecordingCompanionRoute: CompanionPlaybackRouting {
    let watchOwnsAudio = true
    var action: CompanionPlayback.Action?
    var song: Song?
    var queue: [Song]?
    func playbackDidChange(periodic: Bool) {}
    func routeToWatch(_ action: CompanionPlayback.Action, song: Song?, queue: [Song]?,
                      position: Double?, streamURL: URL?, artworkURL: URL?,
                      shuffleEnabled: Bool?, sleepMinutes: Int?, sleepAtEndOfSong: Bool?) -> Bool {
        self.action = action
        self.song = song
        self.queue = queue
        return true
    }
}
