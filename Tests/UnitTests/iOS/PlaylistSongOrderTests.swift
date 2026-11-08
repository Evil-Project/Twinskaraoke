import Foundation
import Testing
@testable import Twinskaraoke

/// List routes send a playlist's songs in no particular order, each with its
/// place in `order`. The playlist screen sorts them; everything else that
/// showed or played them straight from a list didn't, so a setlist's Play from
/// a long-press menu started with whichever song the server listed first.
@Suite("Playlist song order")
struct PlaylistSongOrderTests {
    /// Songs the way a list route sends them: places 3, 1 and 2, then two
    /// songs without a place.
    private let songsJSON = """
        [{"id":"s3","title":"Three","order":3},{"id":"s1","title":"One","order":1},
         {"id":"u1","title":"Unplaced one"},{"id":"s2","title":"Two","order":2},
         {"id":"u2","title":"Unplaced two"}]
        """
    private let expected = ["s1", "s2", "s3", "u1", "u2"]

    private func playlistJSON(_ extra: String = "") -> Data {
        Data(#"{"id":"p","name":"Setlist","songCount":5,\#(extra)"songListDTOs":\#(songsJSON)}"#.utf8)
    }

    @Test("A playlist from a list route has its songs in playlist order")
    func playlist() throws {
        let playlist = try JSONDecoder().decode(Playlist.self, from: playlistJSON())
        #expect(playlist.songListDTOs?.map(\.id) == expected)
    }

    @Test("A paged list item keeps playlist order when it becomes a playlist")
    func listItem() throws {
        let item = try JSONDecoder().decode(PlaylistListItem.self, from: playlistJSON())
        #expect(item.asPlaylist().songListDTOs?.map(\.id) == expected)
    }

    @Test("The user's own playlists are in playlist order")
    func userPlaylist() throws {
        let playlist = try JSONDecoder().decode(UserPlaylist.self, from: playlistJSON())
        #expect(playlist.asPlaylist().songListDTOs?.map(\.id) == expected)
    }

    @Test("Playlists decoded from a list response are in playlist order")
    func listResponse() throws {
        let data = Data("[".utf8) + playlistJSON() + Data("]".utf8)
        let playlists = try KaraokeAPIClient.decodePlaylists(from: data)
        #expect(playlists.first?.songListDTOs?.map(\.id) == expected)
    }

    @Test("A setlist's songs are in sung order")
    func setlist() throws {
        let setlist = try JSONDecoder().decode(
            KaraokeSetlist.self,
            from: playlistJSON(#""setListDate":"2026-10-29T00:00:00","#)
        )
        #expect(setlist.playlist.songListDTOs?.map(\.id) == expected)
    }

    @Test("Saved playlists come back in playlist order")
    func savedPlaylistRoundTrip() throws {
        let unsorted = try JSONDecoder().decode([Song].self, from: Data(songsJSON.utf8))
        let saved = Playlist(id: "p", name: "Saved", songCount: 5, mosaicMedia: nil, songListDTOs: unsorted)
        let restored = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(saved))
        #expect(restored.songListDTOs?.map(\.id) == expected)
    }
}
