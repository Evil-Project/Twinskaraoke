import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class FavoritesManager {
    static let shared = FavoritesManager()
    private(set) var favoriteIDs: Set<String> = []

    /// Favorites live in the account, so changing them needs a signed-in
    /// session and `toggle` ignores anything else. Controls read this to stay
    /// out of the way when signed out, instead of acknowledging a tap with a
    /// success haptic and then doing nothing.
    ///
    /// Stored rather than read straight from the keychain so views update: the
    /// sign-in and sign-out paths already call `reload()` and `clear()`.
    private(set) var isAvailable = CredentialStore.isAuthenticated
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
        refreshAvailability()
        guard !loaded, !isLoading else { return }
        if let lastLoadFailure, Date().timeIntervalSince(lastLoadFailure) < loadFailureRetryDelay {
            return
        }
        Task { @MainActor in await load() }
    }

    func reload() {
        refreshAvailability()
        guard !isLoading else { return }
        Task { @MainActor in await load() }
    }

    func clear() {
        refreshAvailability()
        stateGeneration += 1
        favoriteIDs = []
        inFlight = []
        loaded = false
        isLoading = false
        lastLoadFailure = nil
        mutationRevision = 0
        reloadAfterMutations = false
    }

    private func refreshAvailability() {
        let available = CredentialStore.isAuthenticated
        if isAvailable != available { isAvailable = available }
    }

    func toggle(songID: String) {
        refreshAvailability()
        guard isAvailable else { return }
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
        guard CredentialStore.isAuthenticated, !isLoading else { return }
        let generation = stateGeneration
        let revision = mutationRevision
        isLoading = true
        defer {
            if stateGeneration == generation {
                isLoading = false
                scheduleReloadAfterMutationsIfNeeded()
            }
        }
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
    func moveFavorite(songID: String, from oldOrder: Int, to newOrder: Int) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        guard let req = try? KaraokeAPIClient.jsonArrayRequest(
            pathSegments: ["api", "user", "favorites", "save-order"],
            body: KaraokeAPIClient.songMovePayload(songID: songID, from: oldOrder, to: newOrder)
        ) else { return false }
        guard (try? await KaraokeAPIClient.data(for: req)) != nil else { return false }
        await KaraokeAPIClient.invalidateFavoriteSongs()
        return true
    }
    func add(songID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        guard !inFlight.contains(songID) else { return false }
        guard !favoriteIDs.contains(songID) else { return true }

        let generation = beginMutation(songID)
        defer { endMutation(songID, generation: generation) }

        guard await send(songID: songID) else { return false }
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.insert(songID)
        return true
    }
    func remove(songID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        guard !inFlight.contains(songID) else { return false }
        guard var req = try? KaraokeAPIClient.request(
            pathSegments: ["api", "user", "favorites", songID]
        ) else { return false }
        req.httpMethod = "DELETE"

        let generation = beginMutation(songID)
        defer { endMutation(songID, generation: generation) }

        let ok: Bool
        do {
            _ = try await KaraokeAPIClient.data(for: req)
            ok = true
        } catch KaraokeAPIClient.APIError.httpStatus(404) {
            ok = true
        } catch {
            ok = false
        }
        guard ok else { return false }
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.remove(songID)
        return true
    }
    private func beginMutation(_ songID: String) -> Int {
        inFlight.insert(songID)
        mutationRevision &+= 1
        if isLoading {
            reloadAfterMutations = true
        }
        return stateGeneration
    }

    private func endMutation(_ songID: String, generation: Int) {
        guard stateGeneration == generation else { return }
        inFlight.remove(songID)
        scheduleReloadAfterMutationsIfNeeded()
    }

    private func send(songID: String) async -> Bool {
        guard var req = try? KaraokeAPIClient.request(
            pathSegments: ["api", "user", "favorites", songID]
        )
        else { return false }
        req.httpMethod = "PUT"
        // This endpoint flips membership, so repeating a successful write
        // after a lost response would undo the user's change.
        return (try? await KaraokeAPIClient.data(for: req, allowsRetry: false)) != nil
    }
}
