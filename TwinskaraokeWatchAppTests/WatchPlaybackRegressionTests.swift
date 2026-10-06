import Foundation
import MediaPlayer
import UIKit
import WatchConnectivity
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Watch playback regressions")
struct WatchPlaybackRegressionTests {
    @MainActor
    @Test("MediaPlayer can request cached artwork on a background thread")
    func backgroundArtworkRequest() async throws {
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0fQAAAAASUVORK5CYII="))
        let image = try #require(UIImage(data: imageData))
        let artwork = AudioManager.makeNowPlayingArtwork(image)
        let request = BackgroundArtworkRequest(artwork: artwork)
        let size = await Task.detached { request.imageSize() }.value
        #expect(size == CGSize(width: 1, height: 1))
    }

    @Test("Personal playlists decode without optional server presentation flags")
    func missingPlaylistFields() throws {
        let data = Data(#"[{"id":"mine","name":"My Mix","songListDTOs":[{"id":"one","title":"Song"}]}]"#.utf8)
        let playlists = try JSONDecoder().decode([UserPlaylist].self, from: data)
        #expect(playlists.first?.asPlaylist().songCount == 1)
        #expect(playlists.first?.asPlaylist().isPersonal == true)
    }

    @Test("Touch seeking maps linearly and clamps invalid or out-of-range gestures")
    func touchSeeking() {
        #expect(WatchPlaybackPosition.time(at: 25, width: 100, duration: 240) == 60)
        #expect(WatchPlaybackPosition.time(at: -20, width: 100, duration: 240) == 0)
        #expect(WatchPlaybackPosition.time(at: 120, width: 100, duration: 240) == 240)
        #expect(WatchPlaybackPosition.time(at: .nan, width: 100, duration: 240) == 0)
        #expect(WatchPlaybackPosition.time(at: 50, width: 0, duration: 240) == 0)
    }

    @MainActor
    @Test("A personal playlist without inline covers obtains artwork from its details")
    func personalCoverFallback() async {
        var partial = Playlist(id: "mine", name: "Mix", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        partial.isPersonal = true
        let full = Playlist(id: "mine", name: "Mix", songCount: 1,
            mosaicMedia: [Media(absolutePath: "https://example.com/already-resized.jpg")], songListDTOs: nil)
        let loader = WatchPlaylistCoverLoader(loadDetail: { _ in full })
        await loader.load(partial)
        #expect(loader.urls.first?.absoluteString == "https://example.com/already-resized.jpg")
    }

    @Test("Download errors distinguish denied access from missing audio")
    func downloadResponseErrors() {
        let url = URL(string: "https://example.com/audio")!
        #expect(WatchDownloads.responseError(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))?.contains("sync your account") == true)
        #expect(WatchDownloads.responseError(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))?.contains("unavailable") == true)
    }

    @Test("A full thousand-song playlist survives a bounded companion message")
    func largePlaylistMessage() throws {
        let queue = (0..<1000).map { UITestFixtures.song(id: "song-\($0)", title: "A personal playlist song \($0)", artist: "Artist") }
        let command = CompanionPlayback.Command(action: .play, song: queue[0], queue: queue, shuffleEnabled: true)
        let data = try #require(CompanionPlayback.encode(command))
        #expect(data.count < 60_000)
        #expect(CompanionPlayback.encode(command) == data)
        let decoded = try #require(CompanionPlayback.decode(CompanionPlayback.Command.self, from: data))
        #expect(decoded.queue?.count == 1000)
        #expect(decoded.shuffleEnabled == true)
        #expect(decoded.queue == queue)
    }

    @Test("Saved JSON from a previous build remains readable")
    func legacyJSON() throws {
        let command = CompanionPlayback.Command(action: .pause)
        let data = try JSONEncoder().encode(command)
        #expect(CompanionPlayback.decode(CompanionPlayback.Command.self, from: data)?.id == command.id)
        #expect(CompanionPlayback.decode(CompanionPlayback.Command.self, from: Data("NKP1broken".utf8)) == nil)
    }

    @Test("Oversized playlists do not report a disconnected phone")
    func payloadError() {
        let error = NSError(domain: WCErrorDomain, code: WCError.Code.payloadTooLarge.rawValue)
        #expect(WatchAuthManager.playbackMessageError(error).contains("playlist is too large"))
    }

    @MainActor
    @Test("Companion sleep deadlines mirror without triggering a second expiry")
    func sleepMirror() {
        var expired = false
        let timer = SleepTimer { expired = true }
        timer.mirror(deadline: Date().addingTimeInterval(60), endsWithCurrentSong: false)
        #expect(timer.isActive)
        timer.checkExpiry(now: Date().addingTimeInterval(120))
        #expect(!expired)
        #expect(timer.isActive)
        timer.cancel()
        #expect(!timer.isActive)
        #expect(!expired)
        timer.startEndOfSong()
        #expect(timer.consumeEndOfSong())
        #expect(!timer.consumeEndOfSong())
    }
}

// MediaPlayer invokes the escaping request handler from outside Swift's actor
// model. This wrapper deliberately reproduces that framework boundary.
nonisolated private struct BackgroundArtworkRequest: @unchecked Sendable {
    let artwork: MPMediaItemArtwork
    func imageSize() -> CGSize? { artwork.image(at: CGSize(width: 1, height: 1))?.size }
}
