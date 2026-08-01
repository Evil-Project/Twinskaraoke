import Combine
import Foundation

@MainActor
final class UserPlaylistsManager: ObservableObject {
    typealias PlaylistLoader = @Sendable () async throws -> [UserPlaylist]
    typealias CreatePlaylistSender = @Sendable (
        _ name: String,
        _ description: String?,
        _ isPublic: Bool,
        _ sessionScope: UserSessionScope
    ) async -> Bool
    typealias AddSongSender = @Sendable (
        _ songID: String,
        _ playlistID: String,
        _ sessionScope: UserSessionScope
    ) async -> Bool
    typealias SessionScopeProvider = @MainActor () -> UserSessionScope

    static let shared = UserPlaylistsManager()

    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var isLoading = false

    private var loaded = false
    private var loadTask: Task<Void, Never>?
    private var mutationTasks: [UUID: Task<Void, Never>] = [:]
    private var stateGeneration: UInt64 = 0
    private var loadGeneration: UInt64 = 0
    private var activeSessionScope: UserSessionScope
    private let playlistLoader: PlaylistLoader
    private let createPlaylistSender: CreatePlaylistSender
    private let addSongSender: AddSongSender
    private let sessionScopeProvider: SessionScopeProvider

    init(
        playlistLoader: @escaping PlaylistLoader = {
            let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
            let data = try await KaraokeAPIClient.data(for: request)
            return try JSONDecoder().decode([UserPlaylist].self, from: data)
        },
        createPlaylistSender: @escaping CreatePlaylistSender = UserPlaylistsManager.sendCreatePlaylist,
        addSongSender: @escaping AddSongSender = UserPlaylistsManager.sendAddSong,
        sessionScopeProvider: @escaping SessionScopeProvider = { UserSessionScope.current }
    ) {
        self.playlistLoader = playlistLoader
        self.createPlaylistSender = createPlaylistSender
        self.addSongSender = addSongSender
        self.sessionScopeProvider = sessionScopeProvider
        activeSessionScope = sessionScopeProvider()
    }

    deinit {
        loadTask?.cancel()
        mutationTasks.values.forEach { $0.cancel() }
    }

    func loadIfNeeded() {
        fetchPlaylists(force: false)
    }

    func fetchPlaylists(force: Bool = true) {
        synchronizeSessionIfNeeded()
        guard activeSessionScope.authenticationToken != nil else {
            playlists = []
            loaded = false
            return
        }
        if isLoading {
            guard force else { return }
            cancelLoad()
        }
        guard force || !loaded else { return }

        loadGeneration &+= 1
        let requestGeneration = loadGeneration
        let sessionGeneration = stateGeneration
        let sessionScope = activeSessionScope
        let playlistLoader = playlistLoader
        isLoading = true

        loadTask = Task { @MainActor [weak self, playlistLoader] in
            do {
                let decoded = try await playlistLoader()
                guard let self else { return }
                synchronizeSessionIfNeeded()
                guard isCurrentLoad(
                    requestGeneration: requestGeneration,
                    sessionGeneration: sessionGeneration,
                    sessionScope: sessionScope
                ) else { return }

                playlists = decoded
                loaded = true
                isLoading = false
                loadTask = nil
                RecentlyAddedTracker.shared.registerIfNew(decoded.map(\.id))
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
            }
        }
    }

    func createPlaylist(
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        synchronizeSessionIfNeeded()
        guard activeSessionScope.authenticationToken != nil else {
            completion?(false)
            return
        }

        let operationID = UUID()
        let sessionGeneration = stateGeneration
        let sessionScope = activeSessionScope
        let createPlaylistSender = createPlaylistSender
        let task = Task { @MainActor [weak self, createPlaylistSender] in
            guard let self else { return }
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else {
                completion?(false)
                return
            }

            let succeeded = await createPlaylistSender(
                name,
                description,
                isPublic,
                sessionScope
            )
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else {
                completion?(false)
                return
            }

            mutationTasks[operationID] = nil
            if succeeded {
                fetchPlaylists(force: true)
            }
            completion?(succeeded)
        }
        mutationTasks[operationID] = task
    }

    func addSong(
        _ songID: String,
        toPlaylist playlistID: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        synchronizeSessionIfNeeded()
        guard activeSessionScope.authenticationToken != nil else {
            completion?(false)
            return
        }

        let operationID = UUID()
        let sessionGeneration = stateGeneration
        let sessionScope = activeSessionScope
        let addSongSender = addSongSender
        let task = Task { @MainActor [weak self, addSongSender] in
            guard let self else { return }
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else {
                completion?(false)
                return
            }

            let succeeded = await addSongSender(songID, playlistID, sessionScope)
            synchronizeSessionIfNeeded()
            guard stateGeneration == sessionGeneration,
                  activeSessionScope == sessionScope,
                  !Task.isCancelled
            else {
                completion?(false)
                return
            }

            mutationTasks[operationID] = nil
            completion?(succeeded)
        }
        mutationTasks[operationID] = task
    }

    func clear() {
        resetState(for: sessionScopeProvider())
    }

    nonisolated private static func sendCreatePlaylist(
        name: String,
        description: String?,
        isPublic: Bool,
        sessionScope: UserSessionScope
    ) async -> Bool {
        var body: [String: Any] = [
            "Name": name,
            "IsPublic": isPublic,
            "IsSetList": false,
        ]
        if let description, !description.isEmpty {
            body["Description"] = description
        }

        do {
            let request = try KaraokeAPIClient.jsonRequest(
                path: "/api/playlist/save",
                body: body,
                authenticationToken: sessionScope.authenticationToken,
                guestID: sessionScope.guestID
            )
            _ = try await KaraokeAPIClient.data(for: request)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func sendAddSong(
        songID: String,
        playlistID: String,
        sessionScope: UserSessionScope
    ) async -> Bool {
        do {
            var request = try KaraokeAPIClient.request(
                path: "/api/user/playlists/\(playlistID)",
                queryItems: [URLQueryItem(name: "songId", value: songID)],
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

    private func synchronizeSessionIfNeeded() {
        let currentScope = sessionScopeProvider()
        guard currentScope != activeSessionScope else { return }
        resetState(for: currentScope)
    }

    private func resetState(for sessionScope: UserSessionScope) {
        stateGeneration &+= 1
        activeSessionScope = sessionScope
        cancelLoad()
        mutationTasks.values.forEach { $0.cancel() }
        mutationTasks.removeAll()
        playlists = []
        loaded = false
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
}
