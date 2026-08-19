import Foundation
import Observation

/// The signed-in listener's own playlists.
///
/// Read-only on the watch: creating playlists and adding songs stay on the
/// phone, so this deliberately does not mirror `UserPlaylistsManager`. Results
/// are mapped to `Playlist` so the existing watch grid and detail views work
/// unchanged.
@MainActor
@Observable
final class UserPlaylistsViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let isAuthenticated: @Sendable () -> Bool
    @ObservationIgnored private let loadPlaylists: @Sendable () async throws -> [Playlist]

    init(
        isAuthenticated: @escaping @Sendable () -> Bool = { CredentialStore.isAuthenticated },
        loadPlaylists: @escaping @Sendable () async throws -> [Playlist] = {
            let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
            let data = try await KaraokeAPIClient.data(for: request)
            return try JSONDecoder()
                .decode([UserPlaylist].self, from: data)
                .map { $0.asPlaylist() }
        }
    ) {
        self.isAuthenticated = isAuthenticated
        self.loadPlaylists = loadPlaylists
    }

    isolated deinit {
        loadTask?.cancel()
    }

    func fetch(force: Bool = false) {
        guard isAuthenticated() else {
            cancelLoad()
            playlists = []
            loadError = nil
            return
        }
        guard !isLoading else { return }
        guard force || playlists.isEmpty else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        let loader = loadPlaylists
        isLoading = true
        loadError = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await loader()
                try Task.checkCancellation()
                guard let self, self.loadGeneration == generation else { return }
                self.playlists = loaded
                self.finishLoad(generation: generation)
            } catch is CancellationError {
                self?.finishLoad(generation: generation)
            } catch {
                guard let self, self.loadGeneration == generation else { return }
                self.loadError = "Check your connection and try again."
                self.finishLoad(generation: generation)
            }
        }
    }

    /// Called when the watch loses its session, so another account's playlists
    /// can't linger on screen.
    func reset() {
        cancelLoad()
        playlists = []
        loadError = nil
    }

    private func cancelLoad() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func finishLoad(generation: Int) {
        guard loadGeneration == generation else { return }
        loadTask = nil
        isLoading = false
    }
}
