import Foundation

/// Queries private library data only in the app; the extension uses sanitized snapshots.
@MainActor
enum PlaylistIntentRepository {
    static func localPlaylists() -> [Playlist] {
        let signedIn = CredentialStore.isAuthenticated
        var values: [Playlist] = []
        if signedIn {
            values.append(Playlist(id: Playlist.favoritesID, name: String(localized: "Favorites"), songCount: FavoritesManager.shared.favoriteIDs.count, mosaicMedia: nil, songListDTOs: nil, isPersonal: true))
        }
        values += PinnedPlaylistsStore.shared.playlists + RecentlyPlayedStore.shared.playlists
        if signedIn { values += UserPlaylistsManager.shared.playlists.map { $0.asPlaylist() } }
        values += SavedPlaylistsStore.shared.playlists
        return unique(values.filter { signedIn || (!$0.isPersonal && !$0.isFavorites) })
    }
    // Present only collections the app already knows. Catalog search happens
    // when a person enters a name, avoiding slow startup and dozens of tiles.
    static func suggestions() async -> [Playlist] { localPlaylists() }
    static func search(_ string: String) async throws -> [Playlist] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return await suggestions() }
        let local = await suggestions().filter { $0.name.localizedCaseInsensitiveContains(query) }
        var remote: [Playlist] = []
        for isSetlist in [true, false] {
            do {
                let request = try KaraokeAPIClient.request(path: "/api/playlists", queryItems: [
                    URLQueryItem(name: "search", value: query), URLQueryItem(name: "startIndex", value: "0"),
                    URLQueryItem(name: "pageSize", value: "25"), URLQueryItem(name: "isSetlist", value: isSetlist ? "True" : "False"),
                    URLQueryItem(name: "sortDescending", value: "True"), URLQueryItem(name: "year", value: "0")
                ])
                remote += try KaraokeAPIClient.decodePlaylists(from: await KaraokeAPIClient.data(for: request))
            } catch {
                if local.isEmpty && remote.isEmpty && !isSetlist { throw error }
            }
        }
        return unique(local + remote)
    }
    nonisolated static func snapshot(_ playlist: Playlist) -> WidgetPlaylist {
        WidgetPlaylist(id: playlist.id, name: playlist.name, songCount: playlist.songCount,
                       isPersonal: playlist.isPersonal || playlist.isFavorites,
                       artworkFilename: playlist.thumbnailURL.map { WidgetArtworkStore.filename(for: $0.absoluteString) })
    }
    private static func unique(_ values: [Playlist]) -> [Playlist] {
        var ids = Set<String>()
        return values.filter { ids.insert($0.id).inserted }
    }
}
