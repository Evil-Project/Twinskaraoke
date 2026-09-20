import Foundation
import Observation
@MainActor
@Observable
final class FavoritesViewModel {
    var songs: [Song] = []
    var isLoading = false
    var loadError: String?
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
                self.loadError = String(localized: "Check your connection and try again.")
                self.finishLoad(generation: generation)
            }
        }
    }
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
