import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

/// Opening one of your own playlists on the watch.
///
/// `/api/user/playlists` returns each playlist with its songs inline, and the
/// curated detail endpoint the watch asks afterwards has never heard of a
/// personal playlist ID. The route is the only place those inline songs can
/// survive the push, so this pins that they do.
@Suite("Watch personal playlist routing")
struct WatchPersonalPlaylistRoutingTests {
    @Test("A personal playlist carries its songs to the detail screen")
    func personalRouteCarriesSongs() {
        let route = PlaylistRoute(playlist: makePlaylist(isPersonal: true))

        #expect(route.fallbackSongs.map(\.id) == ["song-1", "song-2"])
    }

    /// Curated playlists come back from the list endpoint without their songs,
    /// and the detail endpoint knows them — carrying a partial list would only
    /// give the screen something stale to show first.
    @Test("A curated playlist carries none")
    func curatedRouteCarriesNoSongs() {
        let route = PlaylistRoute(playlist: makePlaylist(isPersonal: false))

        #expect(route.fallbackSongs.isEmpty)
    }

    /// `navigationDestination(for:)` matches on the value, so a route rebuilt
    /// after a refresh has to still be the same destination as the one already
    /// on the stack.
    @Test("Identity is the playlist, not the songs it was routed with")
    func routeIdentityIgnoresSongs() {
        let withSongs = PlaylistRoute(playlist: makePlaylist(isPersonal: true))
        let withoutSongs = PlaylistRoute(playlist: makePlaylist(isPersonal: false))

        #expect(withSongs == withoutSongs)
        #expect(withSongs.hashValue == withoutSongs.hashValue)
    }

    @MainActor
    @Test("The detail screen shows the inline songs before any fetch answers")
    func detailStartsFromFallback() {
        let route = PlaylistRoute(playlist: makePlaylist(isPersonal: true))
        let viewModel = PlaylistDetailViewModel(
            playlistID: route.id,
            fallbackSongs: route.fallbackSongs
        )

        #expect(viewModel.songs.map(\.id) == ["song-1", "song-2"])
        #expect(viewModel.loadError == nil)
    }

    @MainActor
    @Test("A curated playlist still starts empty")
    func curatedDetailStartsEmpty() {
        let viewModel = PlaylistDetailViewModel(playlistID: "curated-1")

        #expect(viewModel.songs.isEmpty)
    }

    private func makePlaylist(isPersonal: Bool) -> Playlist {
        Playlist(
            id: "playlist-1",
            name: "My Mix",
            songCount: 2,
            mosaicMedia: nil,
            songListDTOs: [makeSong(id: "song-1"), makeSong(id: "song-2")],
            isPersonal: isPersonal
        )
    }

    private func makeSong(id: String) -> Song {
        Song(
            id: id,
            title: id,
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: nil
        )
    }
}
