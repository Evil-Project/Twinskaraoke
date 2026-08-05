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

    /// The sidebar lists only the signed-in user's own playlists. Public
    /// playlists used to fall back into this list, which buried the rest of the
    /// sidebar under dozens of rows nobody asked for — they live in Library now.
    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard CredentialStore.isAuthenticated else {
            playlists = []
            hasLoaded = true
            return
        }

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
            playlists = []
            errorMessage = "Couldn't load your playlists."
        }
    }

    /// Called when the signed-in user changes: their playlists are a different
    /// set, so drop the cached load and fetch again.
    func invalidate() {
        hasLoaded = false
    }
}

/// Public playlists, shown in Library. Available signed out, which is why it's
/// separate from the user's own list rather than a fallback inside it.
@MainActor
@Observable
final class MacLibraryViewModel {
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
            playlists = try await KaraokeAPIClient.publicPlaylists(
                startIndex: 0,
                pageSize: 100
            )
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load the library."
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
