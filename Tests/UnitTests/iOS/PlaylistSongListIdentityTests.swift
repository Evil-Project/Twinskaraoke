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

    private static func song(_ id: String) -> Song {
        Song(
            id: id,
            title: id,
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )
    }
}
