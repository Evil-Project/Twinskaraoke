import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class FavoritesManager {
    static let shared = FavoritesManager()
    static let didSave = Notification.Name("FavoritesDidSave")
    static let didRefresh = Notification.Name("FavoritesDidRefresh")
    private(set) var favoriteIDs: Set<String> = []

    /// Favorites live in the account, so changing them needs a signed-in
    /// session and `toggle` ignores anything else. Controls read this to stay
    /// out of the way when signed out, instead of acknowledging a tap with a
    /// success haptic and then doing nothing.
    ///
    /// Stored rather than read straight from the keychain so views update: the
    /// sign-in and sign-out paths already call `reload()` and `clear()`.
    private(set) var isAvailable: Bool
    @ObservationIgnored private let authenticated: @MainActor () -> Bool
    @ObservationIgnored private let fetchSongs: @MainActor () async throws -> [Song]
    /// Writes one song's membership: `true` adds it, `false` removes it.
    @ObservationIgnored private let setFavorite: @MainActor (String, Bool) async -> Bool

    init(authenticated: @escaping @MainActor () -> Bool = { CredentialStore.isAuthenticated },
         fetchSongs: @escaping @MainActor () async throws -> [Song] = { try await KaraokeAPIClient.favoriteSongs() },
         setFavorite: @escaping @MainActor (String, Bool) async -> Bool = {
             await FavoritesManager.send(songID: $0, favorite: $1)
         }) {
        self.authenticated = authenticated
        self.fetchSongs = fetchSongs
        self.setFavorite = setFavorite
        isAvailable = authenticated()
    }
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

    /// Refresh from the server after the companion saves, without emitting a
    /// second mutation notification. Existing loads cannot overwrite this one.
    func refreshFromCompanion() async {
        let generation = stateGeneration
        mutationRevision &+= 1
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard generation == stateGeneration else { return }
        if !isLoading, inFlight.isEmpty {
            await load()
        } else {
            reloadAfterMutations = true
        }
        guard generation == stateGeneration else { return }
        NotificationCenter.default.post(name: Self.didRefresh, object: self)
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
        let available = authenticated()
        if isAvailable != available { isAvailable = available }
    }

    @discardableResult
    func toggle(songID: String) -> Task<Void, Never>? {
        refreshAvailability()
        guard isAvailable else { return nil }
        guard !inFlight.contains(songID) else { return nil }
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
        return Task {
            let ok = await setFavorite(songID, !wasFavorite)
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
                if ok { NotificationCenter.default.post(name: Self.didSave, object: self) }
                scheduleReloadAfterMutationsIfNeeded()
            }
        }
    }

    private func load() async {
        guard authenticated(), !isLoading else { return }
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
            songs = try await fetchSongs()
        } catch where Self.isCancellation(error) {
            // Invalidating the favorites cache cancels a fetch in flight; at
            // launch the companion refresh does exactly that to the first load.
            // Whoever invalidated either reloads or leaves `loaded` false for
            // the next `loadIfNeeded()`, so this is superseded, not failed, and
            // must not start the retry backoff.
            DebugLogger.log("Favorites load superseded by a newer request", category: .network)
            return
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

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
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
        guard authenticated() else { return false }
        let generation = stateGeneration
        guard let req = try? KaraokeAPIClient.jsonArrayRequest(
            pathSegments: ["api", "user", "favorites", "save-order"],
            body: KaraokeAPIClient.songMovePayload(songID: songID, from: oldOrder, to: newOrder)
        ) else { return false }
        guard (try? await KaraokeAPIClient.data(for: req)) != nil else { return false }
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        NotificationCenter.default.post(name: Self.didSave, object: self)
        return true
    }

    /// Adds without flipping. Safe to call on a song already favourited.
    func add(songID: String) async -> Bool {
        guard authenticated() else { return false }
        // Refuses to overlap another mutation for the same song, exactly as
        // `toggle` does. Both halves of the check below are unsafe while one is
        // in flight: a removal leaves the ID in `favoriteIDs` until it lands, so
        // the fast path would report success for a song about to disappear.
        // The fast path also keeps a PUT from reaching a song that is already
        // a favorite; see `send` for why that matters.
        // Reporting failure lets the caller show it and retry.
        guard !inFlight.contains(songID) else { return false }
        guard !favoriteIDs.contains(songID) else { return true }

        let generation = beginMutation(songID)
        defer { endMutation(songID, generation: generation) }

        guard await setFavorite(songID, true) else { return false }
        // Invalidated before the generation check, matching `toggle`: if
        // `clear()` lands mid-request the cache still holds the pre-mutation
        // list, and a later load would read it as current.
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.insert(songID)
        NotificationCenter.default.post(name: Self.didSave, object: self)
        return true
    }

    /// Unconditional removal for multi-select delete. Unlike `toggle` it
    /// doesn't depend on the current star state, so a song already gone stays
    /// gone.
    func remove(songID: String) async -> Bool {
        guard authenticated() else { return false }
        // Same non-overlap rule as `add` and `toggle`; see `add`.
        guard !inFlight.contains(songID) else { return false }

        let generation = beginMutation(songID)
        defer { endMutation(songID, generation: generation) }

        guard await setFavorite(songID, false) else { return false }
        // Before the generation check, for the reason given in `add`.
        await KaraokeAPIClient.invalidateFavoriteSongs()
        guard stateGeneration == generation else { return false }
        favoriteIDs.remove(songID)
        NotificationCenter.default.post(name: Self.didSave, object: self)
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

    /// `PUT /api/user/favorites/{songId}` adds, `DELETE` on the same path
    /// removes.
    ///
    /// The PUT is never retried. In 2026-08 the server treated it as a toggle,
    /// so a retry after a lost response would have undone the add. It is meant
    /// to be a plain add now, but nothing is lost by staying cautious. DELETE is
    /// idempotent, so it may retry, and a 404 means the song was already gone,
    /// which is what the caller asked for.
    private static func send(songID: String, favorite: Bool) async -> Bool {
        guard var req = try? KaraokeAPIClient.request(
            pathSegments: ["api", "user", "favorites", songID]
        )
        else { return false }
        guard favorite else {
            req.httpMethod = "DELETE"
            do {
                _ = try await KaraokeAPIClient.data(for: req)
                return true
            } catch KaraokeAPIClient.APIError.httpStatus(404) {
                return true
            } catch {
                return false
            }
        }
        req.httpMethod = "PUT"
        return (try? await KaraokeAPIClient.data(for: req, allowsRetry: false)) != nil
    }
}
