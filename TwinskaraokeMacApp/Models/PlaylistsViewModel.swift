import Foundation
import Observation

@MainActor
@Observable
final class MacPlaylistsViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// True when the list is public playlists rather than the user's own,
    /// so callers can tell "signed out" apart from "you have no playlists".
    private(set) var isShowingPublicFallback = false

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // /api/playlists is auth-only and 401s when signed out. Mirror
        // HomeViewModel.fetchTopPicks: fall back to the public list so the
        // always-visible sidebar has something browsable either way.
        let own = try? await KaraokeAPIClient.playlists(
            startIndex: 0,
            pageSize: 60,
            isSetlist: false,
            sortDescending: true
        )
        if let own, !own.isEmpty {
            playlists = own
            isShowingPublicFallback = false
            hasLoaded = true
            return
        }

        do {
            playlists = try await KaraokeAPIClient.publicPlaylists(
                startIndex: 0,
                pageSize: 60
            )
            isShowingPublicFallback = true
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            // Only surface an error if we have nothing at all to show.
            playlists = []
            errorMessage = "Couldn't load playlists."
        }
    }

    /// Called when the signed-in user changes: their playlists are a different
    /// set, so drop the cached load and fetch again.
    func invalidate() {
        hasLoaded = false
        isShowingPublicFallback = false
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
