import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class FavoritesManager {
    static let shared = FavoritesManager()
    private(set) var favoriteIDs: Set<String> = []
    private var inFlight: Set<String> = []
    private var loaded = false
    private var isLoading = false
    private var lastLoadFailure: Date?
    private var stateGeneration = 0
    private var mutationRevision = 0
    private var reloadAfterMutations = false
    private let loadFailureRetryDelay: TimeInterval = 30

    func isFavorite(_ songID: String) -> Bool {
        favoriteIDs.contains(songID)
    }

    func loadIfNeeded() {
        guard !loaded, !isLoading else { return }
        if let lastLoadFailure, Date().timeIntervalSince(lastLoadFailure) < loadFailureRetryDelay {
            return
        }
        Task { @MainActor in await load() }
    }

    func reload() {
        guard !isLoading else { return }
        Task { @MainActor in await load() }
    }

    func clear() {
        stateGeneration += 1
        favoriteIDs = []
        inFlight = []
        loaded = false
        isLoading = false
        lastLoadFailure = nil
        mutationRevision = 0
        reloadAfterMutations = false
    }

    func toggle(songID: String) {
        guard !inFlight.contains(songID) else { return }
        let wasFavorite = favoriteIDs.contains(songID)
        if wasFavorite {
            favoriteIDs.remove(songID)
        } else {
            favoriteIDs.insert(songID)
        }
        inFlight.insert(songID)
        mutationRevision &+= 1
        if isLoading {
            reloadAfterMutations = true
        }
        let generation = stateGeneration
        Task {
            let ok = await send(songID: songID)
            if ok {
                // Serialize invalidation ahead of the reload below: a racing
                // load()/reload() must not read the pre-toggle list from the
                // cache and commit stale star state as loaded.
                await KaraokeAPIClient.invalidateFavoriteSongs()
            }
            await MainActor.run {
                guard stateGeneration == generation else { return }
                inFlight.remove(songID)
                if !ok {
                    if wasFavorite {
                        favoriteIDs.insert(songID)
                    } else {
                        favoriteIDs.remove(songID)
                    }
                }
                scheduleReloadAfterMutationsIfNeeded()
            }
        }
    }

    private func load() async {
        guard CredentialStore.isAuthenticated else { return }
        let generation = stateGeneration
        let revision = mutationRevision
        isLoading = true
        defer {
            if stateGeneration == generation {
                isLoading = false
                scheduleReloadAfterMutationsIfNeeded()
            }
        }
        // Read from the same source as the Favorites playlist. The old
        // /api/user/favorites ID list did not match the playlist's songs
        // (starred songs showed an inactive star everywhere), while
        // favoriteSongs() returns the complete set and shares the
        // FavoriteSongsCache with the playlist.
        let songs: [Song]
        do {
            songs = try await KaraokeAPIClient.favoriteSongs()
        } catch {
            DebugLogger.log(
                "Favorites load failed: \(error.localizedDescription)",
                category: .network
            )
            if stateGeneration == generation {
                lastLoadFailure = Date()
            }
            return
        }
        guard stateGeneration == generation else { return }
        guard mutationRevision == revision, inFlight.isEmpty else {
            reloadAfterMutations = true
            return
        }
        favoriteIDs = Set(songs.map(\.id))
        loaded = true
        lastLoadFailure = nil
    }

    private func scheduleReloadAfterMutationsIfNeeded() {
        guard reloadAfterMutations, inFlight.isEmpty, !isLoading else { return }
        reloadAfterMutations = false
        Task { @MainActor [weak self] in
            await self?.load()
        }
    }

    private func send(songID: String) async -> Bool {
        guard var req = try? KaraokeAPIClient.request(
            pathSegments: ["api", "user", "favorites", songID]
        )
        else { return false }
        req.httpMethod = "PUT"
        return (try? await KaraokeAPIClient.data(for: req)) != nil
    }
}
