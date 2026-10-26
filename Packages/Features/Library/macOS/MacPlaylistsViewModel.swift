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
