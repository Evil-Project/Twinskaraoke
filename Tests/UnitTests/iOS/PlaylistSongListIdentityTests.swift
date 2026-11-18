import CoreGraphics
import Testing
@testable import Twinskaraoke

/// The playlist screen re-runs its body every 2pt of the pull-to-find. The
/// song list it builds on each of those passes must compare equal, so that
/// `.equatable()` stops the pass before it reaches the rows.
@MainActor
struct PlaylistSongListIdentityTests {
    @Test func aRebuiltSongListComparesEqualUntilItsSongsChange() {
        let playlist = Playlist(id: "mine", name: "Mine", songCount: 2, mosaicMedia: nil, songListDTOs: nil)
        let songs = [Self.song("one"), Self.song("two")]

        let shown = PlaylistSongList(playlist: playlist, songs: songs)
        let rebuilt = PlaylistSongList(playlist: playlist, songs: songs)
        let filtered = PlaylistSongList(playlist: playlist, songs: [songs[1]])
        let narrower = PlaylistSongList(playlist: playlist, songs: songs, rowHorizontalPadding: 0)

        #expect(shown == rebuilt)
        #expect(shown != filtered)
        #expect(shown != narrower)
    }

    /// `Song` compares by id only. The list DTOs a playlist opens with carry
    /// no artists; when the detail fetch lands with the same ids and the
    /// artists filled in, the list must not compare equal, or `.equatable()`
    /// keeps the rows on "Unknown Artist".
    @Test func metadataArrivingForTheSameSongsChangesTheList() {
        let playlist = Playlist(id: "mine", name: "Mine", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        let fromList = PlaylistSongList(playlist: playlist, songs: [Self.song("one")])
        let fromDetail = PlaylistSongList(
            playlist: playlist,
            songs: [Self.song("one", artists: ["Wham!"], duration: 231, cover: "covers/one.jpg")]
        )
        let retitled = PlaylistSongList(playlist: playlist, songs: [Self.song("one", title: "One (Live)")])

        #expect(fromList != fromDetail)
        #expect(fromList != retitled)
    }

    /// A row's Play closure captures the `Song` it was built with, so
    /// `.equatable()` keeping an old row keeps playing the old value. A
    /// refresh that only fills `oss` gives the song its audio URL; the list
    /// must compare unequal, or Play still hands the player a song with none.
    @Test func anAudioSourceArrivingForTheSameSongChangesTheList() {
        let playlist = Playlist(id: "mine", name: "Mine", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        let withoutAudio = PlaylistSongList(playlist: playlist, songs: [Self.song("one")])
        let withOSS = PlaylistSongList(playlist: playlist, songs: [Self.song("one", oss: "audio/one.mp3")])
        let reordered = PlaylistSongList(playlist: playlist, songs: [Self.song("one", order: 3)])

        #expect(Self.song("one").audioURL == nil)
        #expect(Self.song("one", oss: "audio/one.mp3").audioURL != nil)
        #expect(withoutAudio != withOSS)
        #expect(withoutAudio != reordered)
    }

    private static func song(
        _ id: String,
        title: String? = nil,
        artists: [String]? = nil,
        duration: Int = 180,
        cover: String? = nil,
        oss: String? = nil,
        order: Int? = nil
    ) -> Song {
        Song(
            id: id,
            title: title ?? id,
            duration: duration,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: cover.map { Media(absolutePath: $0, cloudflareId: nil) },
            originalArtists: artists,
            coverArtists: nil,
            userUploaded: false,
            oss: oss,
            order: order
        )
    }
}
