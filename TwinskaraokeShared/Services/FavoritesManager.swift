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
        guard CredentialStore.isAuthenticated else { return }
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

    /// Moves one favorite from `oldOrder` to `newOrder`.
    ///
    /// Favorites keep a user-defined order server-side even though this manager
    /// only tracks membership as an unordered `Set`: the ordered list is what
    /// `KaraokeAPIClient.favoriteSongs()` returns, so a successful write is
    /// observed by invalidating that cache rather than by mutating state here.
    ///
    /// Unlike the per-song toggle this is a fixed path — `save-order` is the
    /// literal last segment, not a song ID. One move per call, carrying both
    /// ends of it, for the same reason the playlist route does; see `moveSong`.
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

    /// Adds without flipping. Safe to call on a song already favourited, which
    /// `toggle` is not — see the note on `remove`.
    func add(songID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        // Refuses to overlap another mutation for the same song, exactly as
        // `toggle` does. Both halves of the check below are unsafe while one is
        // in flight: a removal leaves the ID in `favoriteIDs` until it lands, so
        // the fast path would report success for a song about to disappear —
        // and skipping the fast path is worse, because `send` is a PUT that
        // *flips* membership and would remove the song rather than add it.
        // Reporting failure lets the caller show it and retry.
        guard !inFlight.contains(songID) else { return false }
        guard !favoriteIDs.contains(songID) else { return true }

        let generation = beginMutation(songID)
        defer { endMutation(songID, generation: generation) }

        guard await send(songID: songID) else { return false }
        // Invalidated before the generation check, matching `toggle`: if
        // `clear()` lands mid-request the cache still holds the pre-mutation
        // list, and a later load would read it as current.
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.insert(songID)
        return true
    }

    /// Unconditional removal, deliberately not routed through `toggle`.
    ///
    /// `toggle` sends PUT, which *flips* membership. For a multi-select delete
    /// that is the wrong verb twice over: `data(for:)` retries idempotent
    /// requests, so a lost response would re-add the song, and a song already
    /// gone would come back rather than stay removed. DELETE on the same path
    /// is unambiguous, and a 404 means the caller already got what it asked for.
    func remove(songID: String) async -> Bool {
        guard CredentialStore.isAuthenticated else { return false }
        // Same non-overlap rule as `add` and `toggle`; see `add`.
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
        // Before the generation check, for the reason given in `add`.
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.remove(songID)
        return true
    }

    /// Registers a mutation *before* its request is awaited.
    ///
    /// `load()` only commits its result when `mutationRevision` is unchanged and
    /// `inFlight` is empty. A mutation that is not registered satisfies both
    /// conditions for the whole duration of its request, so a load already in
    /// flight can finish afterwards and overwrite the change with the
    /// pre-mutation list — silently un-adding or re-adding a song. `toggle`
    /// has always done this; `add` and `remove` must too.
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
