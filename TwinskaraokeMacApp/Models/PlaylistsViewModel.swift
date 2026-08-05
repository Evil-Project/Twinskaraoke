import Foundation
import Observation

@MainActor
@Observable
final class MacPlaylistsViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlists = try await KaraokeAPIClient.playlists(
                startIndex: 0,
                pageSize: 60,
                isSetlist: false,
                sortDescending: true
            )
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load playlists."
        }
    }
}

/// Songs for one playlist, loaded on demand when a playlist is opened.
@MainActor
@Observable
final class MacPlaylistDetailViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadedID: String?

    func load(playlistID: String) async {
        guard loadedID != playlistID else { return }
        isLoading = true
        errorMessage = nil
        songs = []
        defer { isLoading = false }
        do {
            songs = try await KaraokeAPIClient.playlistSongs(id: playlistID)
            loadedID = playlistID
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load this playlist."
        }
    }
}

/// The signed-in user's favourites, shown as its own sidebar destination.
@MainActor
@Observable
final class MacFavoritesViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            songs = try await KaraokeAPIClient.favoriteSongs()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load your favourites."
        }
    }
}
