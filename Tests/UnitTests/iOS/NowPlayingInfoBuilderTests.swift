import MediaPlayer
import Testing
@testable import Twinskaraoke

@Suite("Now Playing metadata")
@MainActor
struct NowPlayingInfoBuilderTests {
    @Test("On-demand playback publishes bounded timing and preferred artists")
    func onDemandMetadata() {
        let song = fixture(originalArtists: [" Artist A ", "", "Artist B"])
        let info = NowPlayingInfoBuilder.make(
            song: song,
            playbackRate: 1,
            isLiveStream: false,
            duration: 180,
            elapsed: 250,
            existingArtwork: nil
        )

        #expect(info[MPMediaItemPropertyTitle] as? String == "A Song")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Artist A, Artist B")
        #expect(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 180)
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? Double == 180)
    }

    @Test("Live radio omits seekable timing metadata")
    func liveMetadata() {
        let info = NowPlayingInfoBuilder.make(
            song: fixture(originalArtists: nil),
            playbackRate: 1,
            isLiveStream: true,
            duration: 180,
            elapsed: 30,
            existingArtwork: nil
        )

        #expect(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil)
        #expect(info[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(info[MPMediaItemPropertyArtist] as? String == "Cover Artist")
    }

    private func fixture(originalArtists: [String]?) -> Song {
        Song(
            id: "song",
            title: "A Song",
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: originalArtists,
            coverArtists: ["Cover Artist"],
            userUploaded: false
        )
    }
}
