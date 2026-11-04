import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Play count reporting")
@MainActor
struct PlayCountReporterTests {
    private func song(_ id: String) -> Song {
        UITestFixtures.song(id: id, title: id, artist: "Artist")
    }

    @Test("A play is a PUT to the song's playCount route")
    func requestWithoutPlaylist() throws {
        let request = try PlayCountReporter.request(songID: "song-1", playlistID: nil, readToken: { nil })

        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/songs/playCount/song-1")
        #expect(request.url?.query == nil)
    }

    @Test("A play from a playlist carries the playlist ID")
    func requestWithPlaylist() throws {
        let request = try PlayCountReporter.request(songID: "song-1", playlistID: "playlist-1", readToken: { nil })
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems

        #expect(request.url?.path == "/api/songs/playCount/song-1")
        #expect(items == [URLQueryItem(name: "playlistId", value: "playlist-1")])
    }

    @Test("Only songs of the playlist's queue are reported with it")
    func membership() {
        let reporter = PlayCountReporter()
        reporter.queueStarted(fromPlaylist: "playlist-1", songs: [song("a"), song("b")])

        #expect(reporter.playlistID(for: "a") == "playlist-1")
        #expect(reporter.playlistID(for: "b") == "playlist-1")
        // Added with Play Next or Play Last: not part of the playlist.
        #expect(reporter.playlistID(for: "c") == nil)
    }

    @Test("A queue started outside a playlist clears it")
    func otherQueueClears() {
        let reporter = PlayCountReporter()
        reporter.queueStarted(fromPlaylist: "playlist-1", songs: [song("a")])
        reporter.queueStarted(fromPlaylist: nil, songs: [song("a")])

        #expect(reporter.playlistID(for: "a") == nil)
    }

    @Test("Local placeholder IDs like Favorites are never sent", arguments: [Playlist.favoritesID, "__downloads__", ""])
    func placeholdersAreIgnored(id: String) {
        let reporter = PlayCountReporter()
        reporter.queueStarted(fromPlaylist: id, songs: [song("a")])

        #expect(reporter.playlistID(for: "a") == nil)
    }
}
