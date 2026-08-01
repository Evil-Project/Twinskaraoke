import Combine
import Foundation
import SwiftUI

@MainActor
final class FavoritesManager: ObservableObject {
    typealias FavoriteIDsLoader = @Sendable () async throws -> [String]
    typealias ToggleSender = @Sendable (
        _ songID: String,
        _ sessionScope: UserSessionScope
    ) async -> Bool
    typealias SessionScopeProvider = @MainActor () -> UserSessionScope

    static let shared = FavoritesManager()

    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var sessionRevision: UInt64 = 0

    private var inFlight: Set<String> = []
    private var loaded = false
    private var isLoading = false
    private var lastLoadFailure: Date?
    private let loadFailureRetryDelay: TimeInterval = 30
    private var loadTask: Task<Void, Never>?
    private var toggleTasks: [String: Task<Void, Never>] = [:]
    private var stateGeneration: UInt64 = 0
    private var loadGeneration: UInt64 = 0
    private var mutationRevision: UInt64 = 0
    private var needsReloadAfterMutation = false
    private var activeSessionScope: UserSessionScope
    private let favoriteIDsLoader: FavoriteIDsLoader
    private let toggleSender: ToggleSender
    private let sessionScopeProvider: SessionScopeProvider

    init(
        favoriteIDsLoader: @escaping FavoriteIDsLoader = FavoritesManager.loadFavoriteIDs,
        toggleSender: @escaping ToggleSender = FavoritesManager.sendFavoriteToggle,
        sessionScopeProvider: @escaping SessionScopeProvider = { UserSessionScope.current }
    ) {
        self.favoriteIDsLoader = favoriteIDsLoader
        self.toggleSender = toggleSender
        self.sessionScopeProvider = sessionScopeProvider
        activeSessionScope = sessionScopeProvider()
    }

    deinit {
        loadTask?.cancel()
        toggleTasks.values.forEach { $0.cancel() }
    }

    func isFavorite(_ songID: String) -> Bool {
        synchronizeSessionIfNeeded()
        return favoriteIDs.contains(songID)
    }

    func loadIfNeeded() {
        synchronizeSessionIfNeeded()
        guard !loaded, !isLoading else { return }
        if let lastLoadFailure, Date().timeIntervalSince(lastLoadFailure) < loadFailureRetryDelay {
            return
        }
        startLoad(force: false)
    }

    @discardableResult
    func reload() -> Task<Void, Never>? {
        synchronizeSessionIfNeeded()
        return startLoad(force: true)
    }

    func clear() {
        resetState(for: sessionScopeProvider())
    }

    func toggle(songID: String) {
        synchronizeSessionIfNeeded()
        guard !inFlight.contains(songID) else { return }

        let wasFavorite = favoriteIDs.contains(songID)
        if wasFavorite {
            favoriteIDs.remove(songID)
        } else {
            favoriteIDs.insert(songID)
        }
        inFlight.insert(songID)
        mutationRevision &+= 1

        let sessionGeneration = stateGeneration
        let sessionScope = activeSessionScope
        let toggleSender = toggleSender
        toggleTasks[songID] = Task { @MainActor [weak self, toggleSender] in
            guard let self else { return }
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else { return }

            let succeeded = await toggleSender(songID, sessionScope)
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else { return }

            toggleTasks[songID] = nil
            inFlight.remove(songID)
            if !succeeded {
                if wasFavorite {
                    favoriteIDs.insert(songID)
                } else {
                    favoriteIDs.remove(songID)
                }
                needsReloadAfterMutation = true
            }
            startReconciliationIfPossible()
        }
    }

    @discardableResult
    private func startLoad(force: Bool) -> Task<Void, Never>? {
        synchronizeSessionIfNeeded()
        guard inFlight.isEmpty else {
            needsReloadAfterMutation = true
            return nil
        }
        if isLoading {
            guard force else { return nil }
            cancelLoad()
        }
        guard force || !loaded else { return nil }

        loadGeneration &+= 1
        let requestGeneration = loadGeneration
        let sessionGeneration = stateGeneration
        let mutationRevision = mutationRevision
        let sessionScope = activeSessionScope
        let favoriteIDsLoader = favoriteIDsLoader
        isLoading = true

        let task = Task { @MainActor [weak self, favoriteIDsLoader] in
            do {
                let ids = try await favoriteIDsLoader()
                guard let self else { return }
                synchronizeSessionIfNeeded()
                guard isCurrentLoad(
                    requestGeneration: requestGeneration,
                    sessionGeneration: sessionGeneration,
                    sessionScope: sessionScope
                ) else { return }

                isLoading = false
                loadTask = nil
                guard self.mutationRevision == mutationRevision else {
                    loaded = false
                    needsReloadAfterMutation = true
                    startReconciliationIfPossible()
                    return
                }

                favoriteIDs = Set(ids)
                loaded = true
                lastLoadFailure = nil
            } catch {
                guard let self else { return }
                synchronizeSessionIfNeeded()
                guard isCurrentLoad(
                    requestGeneration: requestGeneration,
                    sessionGeneration: sessionGeneration,
                    sessionScope: sessionScope
                ) else { return }

                isLoading = false
                loadTask = nil
                lastLoadFailure = Date()
            }
        }
        loadTask = task
        return task
    }

    private func startReconciliationIfPossible() {
        guard needsReloadAfterMutation, inFlight.isEmpty else { return }
        needsReloadAfterMutation = false
        startLoad(force: true)
    }

    private func synchronizeSessionIfNeeded() {
        let currentScope = sessionScopeProvider()
        guard currentScope != activeSessionScope else { return }
        resetState(for: currentScope)
    }

    private func resetState(for sessionScope: UserSessionScope) {
        stateGeneration &+= 1
        mutationRevision &+= 1
        activeSessionScope = sessionScope
        cancelLoad()
        toggleTasks.values.forEach { $0.cancel() }
        toggleTasks.removeAll()
        inFlight.removeAll()
        favoriteIDs = []
        loaded = false
        lastLoadFailure = nil
        needsReloadAfterMutation = false
        sessionRevision &+= 1
    }

    private func cancelLoad() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func isCurrentLoad(
        requestGeneration: UInt64,
        sessionGeneration: UInt64,
        sessionScope: UserSessionScope
    ) -> Bool {
        requestGeneration == loadGeneration
            && sessionGeneration == stateGeneration
            && sessionScope == activeSessionScope
            && !Task.isCancelled
    }

    nonisolated private static func loadFavoriteIDs() async throws -> [String] {
        let request = try KaraokeAPIClient.request(path: "/api/user/favorites")
        let data = try await KaraokeAPIClient.data(for: request)
        return try decodeFavoriteIDs(from: data)
    }

    nonisolated private static func sendFavoriteToggle(
        songID: String,
        sessionScope: UserSessionScope
    ) async -> Bool {
        let encoded = songID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? songID
        do {
            var request = try KaraokeAPIClient.request(
                path: "/api/user/favorites/\(encoded)",
                authenticationToken: sessionScope.authenticationToken,
                guestID: sessionScope.guestID
            )
            request.httpMethod = "PUT"
            _ = try await KaraokeAPIClient.data(for: request)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func decodeFavoriteIDs(from data: Data) throws -> [String] {
        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw KaraokeAPIClient.APIError.decodeFailed
        }

        if let array = payload as? [Any] {
            return try decodeFavoriteIDArray(array)
        }

        if let object = payload as? [String: Any],
           let value = object["favorites"] ?? object["items"],
           let array = value as? [Any]
        {
            return try decodeFavoriteIDArray(array)
        }

        throw KaraokeAPIClient.APIError.decodeFailed
    }

    nonisolated private static func decodeFavoriteIDArray(_ array: [Any]) throws -> [String] {
        if array.isEmpty { return [] }

        if let ids = array as? [String], ids.count == array.count {
            guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw KaraokeAPIClient.APIError.decodeFailed
            }
            return ids
        }

        guard let objects = array as? [[String: Any]], objects.count == array.count else {
            throw KaraokeAPIClient.APIError.decodeFailed
        }

        return try objects.map { object in
            guard let id = object["id"] as? String ?? object["songId"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw KaraokeAPIClient.APIError.decodeFailed
            }
            return id
        }
    }
}
