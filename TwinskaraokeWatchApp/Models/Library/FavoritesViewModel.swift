import Foundation
import Observation

/// The signed-in listener's favorite songs.
///
/// Reads through `KaraokeAPIClient.favoriteSongs()`, the same source
/// `FavoritesManager` loads from, so the star state on a row and the contents
/// of this list can't disagree.
@MainActor
@Observable
final class FavoritesViewModel {
    var songs: [Song] = []
    var isLoading = false
    /// Set when the initial load fails so the view can offer a retry instead
    /// of showing a misleading empty state.
    var loadError: String?
    /// Set when the phone says we are signed in but the token it holds has not
    /// reached this watch yet. Without it an empty list reads as "no favorites"
    /// when the truth is "could not ask".
    var needsPhoneSession = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let isAuthenticated: @Sendable () -> Bool
    @ObservationIgnored private let loadSongs: @Sendable () async throws -> [Song]

    init(
        isAuthenticated: @escaping @Sendable () -> Bool = { CredentialStore.isAuthenticated },
        loadSongs: @escaping @Sendable () async throws -> [Song] = {
            try await KaraokeAPIClient.favoriteSongs()
        }
    ) {
        self.isAuthenticated = isAuthenticated
        self.loadSongs = loadSongs
    }

    isolated deinit {
        loadTask?.cancel()
    }

    func fetch(force: Bool = false) {
        guard isAuthenticated() else {
            cancelLoad()
            songs = []
            loadError = nil
            needsPhoneSession = true
            return
        }
        guard !isLoading else { return }
        guard force || songs.isEmpty else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        let loader = loadSongs
        needsPhoneSession = false
        isLoading = true
        loadError = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await loader()
                try Task.checkCancellation()
                guard let self, self.loadGeneration == generation else { return }
                self.songs = loaded
                self.needsPhoneSession = false
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

    /// Drops a song the listener just un-starred from this screen, without
    /// waiting for a round trip that would make the row linger.
    func remove(songID: String) {
        songs.removeAll { $0.id == songID }
    }

    func reset() {
        cancelLoad()
        songs = []
        loadError = nil
        needsPhoneSession = false
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
