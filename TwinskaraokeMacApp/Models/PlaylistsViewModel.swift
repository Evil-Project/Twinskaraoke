import Foundation
import Observation

@MainActor
@Observable
final class MacPlaylistsViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false
    private var generation = 0

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }
    func reload() async {
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if requestGeneration == generation { isLoading = false }
        }

        guard CredentialStore.isAuthenticated else {
            playlists = []
            hasLoaded = true
            return
        }

        do {
            let loaded = try await KaraokeAPIClient.playlists(
                startIndex: 0,
                pageSize: 60,
                isSetlist: false,
                sortDescending: true
            )
            guard requestGeneration == generation else { return }
            playlists = loaded
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == generation else { return }
            playlists = []
            errorMessage = String(localized: "Couldn't load your playlists.")
        }
    }
    func invalidate() {
        hasLoaded = false
        generation &+= 1
        playlists = []
        errorMessage = nil
    }
}
@MainActor
@Observable
final class MacLibraryViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false
    private var generation = 0

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.publicPlaylists(
                startIndex: 0,
                pageSize: 100
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }
            playlists = loaded
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load the library.")
        }
    }
}
@MainActor
@Observable
final class MacPlaylistDetailViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadedID: String?
    private var generation = 0

    func load(playlistID: String) async {
        guard loadedID != playlistID else { return }
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        songs = []
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.playlistSongs(id: playlistID)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            songs = loaded
            loadedID = playlistID
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load this playlist.")
        }
    }
}
@MainActor
@Observable
final class MacFavoritesViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = 0

    func reload() async {
        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let loaded = try await KaraokeAPIClient.favoriteSongs()
            guard generation == requestGeneration, !Task.isCancelled else { return }
            songs = loaded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn't load your favourites.")
        }
    }
}
