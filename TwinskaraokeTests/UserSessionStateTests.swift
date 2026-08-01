import Foundation
import SwiftUI
import Testing
@testable import Twinskaraoke

private actor ControlledSessionLoader<Value: Sendable> {
    private var continuations: [Int: CheckedContinuation<Value, Error>] = [:]
    private(set) var requestCount = 0

    func load() async throws -> Value {
        let request = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[request] = continuation
        }
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        while requestCount < expectedCount {
            await Task.yield()
        }
    }

    func succeed(request: Int, with value: Value) {
        guard let continuation = continuations.removeValue(forKey: request) else {
            preconditionFailure("No pending request at index \(request)")
        }
        continuation.resume(returning: value)
    }

    func fail(request: Int, with error: Error) {
        guard let continuation = continuations.removeValue(forKey: request) else {
            preconditionFailure("No pending request at index \(request)")
        }
        continuation.resume(throwing: error)
    }
}

private actor MutationSenderRecorder {
    private var invocationCount = 0

    func record() -> Bool {
        invocationCount += 1
        return true
    }

    func count() -> Int {
        invocationCount
    }
}

@MainActor
private final class MutableSessionScope {
    var value: UserSessionScope

    init(_ value: UserSessionScope) {
        self.value = value
    }
}

@MainActor
@Suite("User session state isolation")
struct UserSessionStateTests {
    @Test("A cleared user-playlist load cannot restore the previous account")
    func playlistLoadIgnoredAfterClear() async throws {
        let loader = ControlledSessionLoader<[UserPlaylist]>()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = UserPlaylistsManager(
            playlistLoader: { try await loader.load() },
            sessionScopeProvider: { session.value }
        )

        manager.fetchPlaylists()
        await loader.waitUntilRequestCount(1)
        session.value = .guest(id: "guest")
        manager.clear()
        await loader.succeed(request: 0, with: [try makeUserPlaylist(id: "old")])
        await drainTasks()

        #expect(manager.playlists.isEmpty)
        #expect(!manager.isLoading)
    }

    @Test("A forced playlist load keeps the new account when the old response finishes last")
    func oldPlaylistResponseIgnoredAfterSessionSwitch() async throws {
        let loader = ControlledSessionLoader<[UserPlaylist]>()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = UserPlaylistsManager(
            playlistLoader: { try await loader.load() },
            sessionScopeProvider: { session.value }
        )

        manager.fetchPlaylists()
        await loader.waitUntilRequestCount(1)
        session.value = .authenticated(token: "new-token")
        manager.fetchPlaylists(force: true)
        await loader.waitUntilRequestCount(2)

        await loader.succeed(request: 1, with: [try makeUserPlaylist(id: "new")])
        await drainTasks()
        await loader.succeed(request: 0, with: [try makeUserPlaylist(id: "old")])
        await drainTasks()

        #expect(manager.playlists.map(\.id) == ["new"])
        #expect(!manager.isLoading)
    }

    @Test("Favorites and personal playlists are session-owned")
    func playlistSessionOwnership() throws {
        let favorites = makePlaylist(id: Playlist.favoritesID)
        let personal = try makeUserPlaylist(id: "personal").asPlaylist()
        let publicPlaylist = makePlaylist(id: "public")

        #expect(favorites.isSessionOwned)
        #expect(personal.isSessionOwned)
        #expect(!publicPlaylist.isSessionOwned)
    }

    @Test("Guest favorites load with their guest identity")
    func guestFavoritesLoad() async {
        let loader = ControlledSessionLoader<[String]>()
        let session = MutableSessionScope(.guest(id: "guest-a"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { try await loader.load() },
            toggleSender: { _, _ in true },
            sessionScopeProvider: { session.value }
        )

        manager.loadIfNeeded()
        await loader.waitUntilRequestCount(1)
        await loader.succeed(request: 0, with: ["guest-song"])
        await drainTasks()

        #expect(manager.favoriteIDs == ["guest-song"])
    }

    @Test("Clearing favorites rejects an in-flight response from the prior session")
    func favoritesLoadIgnoredAfterClear() async {
        let loader = ControlledSessionLoader<[String]>()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { try await loader.load() },
            toggleSender: { _, _ in true },
            sessionScopeProvider: { session.value }
        )

        manager.reload()
        await loader.waitUntilRequestCount(1)
        session.value = .guest(id: "guest")
        manager.clear()
        await loader.succeed(request: 0, with: ["old-song"])
        await drainTasks()

        #expect(manager.favoriteIDs.isEmpty)
        #expect(manager.sessionRevision == 1)
    }

    @Test("Session revision advances even when favorite IDs stay empty")
    func favoritesSessionRevisionAlwaysAdvances() {
        let session = MutableSessionScope(.authenticated(token: "account-a"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { [] },
            toggleSender: { _, _ in true },
            sessionScopeProvider: { session.value }
        )

        session.value = .authenticated(token: "account-b")
        manager.clear()
        #expect(manager.favoriteIDs.isEmpty)
        #expect(manager.sessionRevision == 1)

        session.value = .guest(id: "guest")
        manager.clear()
        #expect(manager.favoriteIDs.isEmpty)
        #expect(manager.sessionRevision == 2)
    }

    @Test("A stale favorites load cannot overwrite an optimistic toggle")
    func staleFavoritesLoadDoesNotOverwriteToggle() async {
        let favoritesLoader = ControlledSessionLoader<[String]>()
        let toggleSender = ControlledSessionLoader<Bool>()
        let session = MutableSessionScope(.authenticated(token: "token"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { try await favoritesLoader.load() },
            toggleSender: { _, _ in (try? await toggleSender.load()) ?? false },
            sessionScopeProvider: { session.value }
        )

        manager.reload()
        await favoritesLoader.waitUntilRequestCount(1)
        manager.toggle(songID: "new-song")
        await toggleSender.waitUntilRequestCount(1)

        await favoritesLoader.succeed(request: 0, with: ["old-song"])
        await drainTasks()
        #expect(manager.favoriteIDs == ["new-song"])

        await toggleSender.succeed(request: 0, with: true)
        await favoritesLoader.waitUntilRequestCount(2)
        await favoritesLoader.succeed(request: 1, with: ["new-song"])
        await drainTasks()

        #expect(manager.favoriteIDs == ["new-song"])
    }

    @Test("A failed toggle cannot roll back into a newer session")
    func toggleFailureIgnoredAfterSessionSwitch() async {
        let toggleSender = ControlledSessionLoader<Bool>()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { [] },
            toggleSender: { _, _ in (try? await toggleSender.load()) ?? false },
            sessionScopeProvider: { session.value }
        )

        manager.toggle(songID: "old-song")
        await toggleSender.waitUntilRequestCount(1)
        #expect(manager.favoriteIDs == ["old-song"])

        session.value = .guest(id: "guest")
        manager.clear()
        await toggleSender.succeed(request: 0, with: false)
        await drainTasks()

        #expect(manager.favoriteIDs.isEmpty)
    }

    @Test("A failed toggle reconciles ambiguous server state")
    func failedToggleReconcilesWithServer() async {
        let favoritesLoader = ControlledSessionLoader<[String]>()
        let toggleSender = ControlledSessionLoader<Bool>()
        let session = MutableSessionScope(.authenticated(token: "token"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { try await favoritesLoader.load() },
            toggleSender: { _, _ in (try? await toggleSender.load()) ?? false },
            sessionScopeProvider: { session.value }
        )

        manager.toggle(songID: "ambiguous-song")
        await toggleSender.waitUntilRequestCount(1)
        await toggleSender.succeed(request: 0, with: false)
        await favoritesLoader.waitUntilRequestCount(1)

        await favoritesLoader.succeed(request: 0, with: ["ambiguous-song"])
        await drainTasks()

        #expect(manager.favoriteIDs == ["ambiguous-song"])
    }

    @Test("A canceled favorite toggle never reaches its sender")
    func canceledFavoriteToggleIsNotDispatched() async {
        let sender = MutationSenderRecorder()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = FavoritesManager(
            favoriteIDsLoader: { [] },
            toggleSender: { _, _ in await sender.record() },
            sessionScopeProvider: { session.value }
        )

        manager.toggle(songID: "old-song")
        session.value = .authenticated(token: "new-token")
        manager.clear()

        await drainTasks()
        let invocationCount = await sender.count()
        #expect(invocationCount == 0)
        #expect(manager.favoriteIDs.isEmpty)
    }

    @Test("A canceled playlist creation never reaches its sender")
    func canceledPlaylistCreationIsNotDispatched() async {
        let sender = MutationSenderRecorder()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = UserPlaylistsManager(
            playlistLoader: { [] },
            createPlaylistSender: { _, _, _, _ in await sender.record() },
            addSongSender: { _, _, _ in true },
            sessionScopeProvider: { session.value }
        )

        manager.createPlaylist(name: "Old playlist")
        session.value = .authenticated(token: "new-token")
        manager.clear()

        await drainTasks()
        let invocationCount = await sender.count()
        #expect(invocationCount == 0)
    }

    @Test("A canceled add-to-playlist mutation never reaches its sender")
    func canceledAddSongIsNotDispatched() async {
        let sender = MutationSenderRecorder()
        let session = MutableSessionScope(.authenticated(token: "old-token"))
        let manager = UserPlaylistsManager(
            playlistLoader: { [] },
            createPlaylistSender: { _, _, _, _ in true },
            addSongSender: { _, _, _ in await sender.record() },
            sessionScopeProvider: { session.value }
        )

        manager.addSong("old-song", toPlaylist: "old-playlist")
        session.value = .authenticated(token: "new-token")
        manager.clear()

        await drainTasks()
        let invocationCount = await sender.count()
        #expect(invocationCount == 0)
    }

    @Test("Scoped API requests bind their captured session credentials")
    func scopedAPIRequestsBindCapturedCredentials() throws {
        let authenticatedRequest = try KaraokeAPIClient.jsonRequest(
            path: "/api/playlist/save",
            body: ["Name": "Playlist"],
            authenticationToken: "captured-token",
            guestID: nil
        )
        #expect(
            authenticatedRequest.value(forHTTPHeaderField: "Authorization")
                == "Bearer captured-token"
        )
        #expect(authenticatedRequest.value(forHTTPHeaderField: "x-guest-id") == nil)

        let guestRequest = try KaraokeAPIClient.request(
            path: "/api/user/favorites/song",
            authenticationToken: nil,
            guestID: "captured-guest"
        )
        #expect(guestRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(guestRequest.value(forHTTPHeaderField: "x-guest-id") == "captured-guest")
    }

    @Test("Forcing public playlists rejects an older completion")
    func publicPlaylistForceRefreshRejectsOldResponse() async {
        let playlistLoader = ControlledSessionLoader<[Playlist]>()
        let viewModel = PlaylistsViewModel(
            playlistLoader: { try await playlistLoader.load() },
            favoriteSongsLoader: { [] },
            sessionScopeProvider: { .guest(id: "guest") }
        )

        viewModel.fetchPlaylists()
        await playlistLoader.waitUntilRequestCount(1)
        viewModel.fetchPlaylists(force: true)
        await playlistLoader.waitUntilRequestCount(2)

        await playlistLoader.succeed(request: 1, with: [makePlaylist(id: "new")])
        await drainTasks()
        await playlistLoader.succeed(request: 0, with: [makePlaylist(id: "old")])
        await drainTasks()

        #expect(viewModel.playlists.map(\.id) == ["new"])
        #expect(!viewModel.isLoading)
    }

    @Test("Library refresh awaits both playlist requests")
    func libraryRefreshAwaitsNetworkCompletion() async {
        let playlistLoader = ControlledSessionLoader<[Playlist]>()
        let favoritesLoader = ControlledSessionLoader<[Song]>()
        let completion = MutationSenderRecorder()
        let viewModel = PlaylistsViewModel(
            playlistLoader: { try await playlistLoader.load() },
            favoriteSongsLoader: { try await favoritesLoader.load() },
            sessionScopeProvider: { .guest(id: "guest") }
        )

        let refreshTask = Task {
            await viewModel.refresh()
            _ = await completion.record()
        }
        await playlistLoader.waitUntilRequestCount(1)
        await favoritesLoader.waitUntilRequestCount(1)
        #expect(await completion.count() == 0)

        await playlistLoader.succeed(request: 0, with: [makePlaylist(id: "playlist")])
        await drainTasks()
        #expect(await completion.count() == 0)

        await favoritesLoader.succeed(request: 0, with: [makeSong(id: "favorite")])
        await refreshTask.value

        #expect(await completion.count() == 1)
        #expect(viewModel.playlists.map(\.id) == ["playlist"])
        #expect(viewModel.favoriteSongs.map(\.id) == ["favorite"])
    }

    @Test("Library refresh awaits a favorite reload requested while refreshing")
    func libraryRefreshAwaitsReplacementFavoriteRequest() async {
        let favoritesLoader = ControlledSessionLoader<[Song]>()
        let completion = MutationSenderRecorder()
        let viewModel = PlaylistsViewModel(
            playlistLoader: { [] },
            favoriteSongsLoader: { try await favoritesLoader.load() },
            sessionScopeProvider: { .guest(id: "guest") }
        )

        let refreshTask = Task {
            await viewModel.refresh()
            _ = await completion.record()
        }
        await favoritesLoader.waitUntilRequestCount(1)

        viewModel.fetchFavoriteSongs(force: true)
        #expect(await favoritesLoader.requestCount == 1)

        await favoritesLoader.succeed(request: 0, with: [makeSong(id: "stale")])
        await favoritesLoader.waitUntilRequestCount(2)
        #expect(await completion.count() == 0)

        await favoritesLoader.succeed(request: 1, with: [makeSong(id: "current")])
        await refreshTask.value

        #expect(await completion.count() == 1)
        #expect(viewModel.favoriteSongs.map(\.id) == ["current"])
        #expect(!viewModel.isLoadingFavorites)
    }

    @Test("A failed forced playlist refresh preserves displayed content")
    func failedPlaylistRefreshPreservesContent() async {
        let playlistLoader = ControlledSessionLoader<[Playlist]>()
        let viewModel = PlaylistsViewModel(
            playlistLoader: { try await playlistLoader.load() },
            favoriteSongsLoader: { [] },
            sessionScopeProvider: { .guest(id: "guest") }
        )

        viewModel.fetchPlaylists()
        await playlistLoader.waitUntilRequestCount(1)
        await playlistLoader.succeed(request: 0, with: [makePlaylist(id: "existing")])
        await drainTasks()

        viewModel.fetchPlaylists(force: true)
        await playlistLoader.waitUntilRequestCount(2)
        await playlistLoader.fail(request: 1, with: URLError(.cannotParseResponse))
        await drainTasks()

        #expect(viewModel.playlists.map(\.id) == ["existing"])
        #expect(!viewModel.isLoading)
    }

    @Test("Songs pull-to-refresh awaits its page request")
    func librarySongsRefreshAwaitsPageRequest() async throws {
        let pageLoader = ControlledSessionLoader<LibrarySongsViewModel.PageResponse>()
        let completion = MutationSenderRecorder()
        let viewModel = LibrarySongsViewModel { _ in
            try await pageLoader.load()
        }
        let responseData = try JSONEncoder().encode([makeSong(id: "song")])

        let refreshTask = Task {
            await viewModel.refresh()
            _ = await completion.record()
        }
        await pageLoader.waitUntilRequestCount(1)
        #expect(await completion.count() == 0)

        await pageLoader.succeed(
            request: 0,
            with: .init(data: responseData, statusCode: 200)
        )
        await refreshTask.value

        #expect(await completion.count() == 1)
        #expect(viewModel.songs.map(\.id) == ["song"])
        #expect(!viewModel.isLoading)
    }

    @Test("Library favorites reject a response from the previous session")
    func libraryFavoritesRejectOldSessionResponse() async {
        let favoritesLoader = ControlledSessionLoader<[Song]>()
        let session = MutableSessionScope(.guest(id: "guest-a"))
        let viewModel = PlaylistsViewModel(
            playlistLoader: { [] },
            favoriteSongsLoader: { try await favoritesLoader.load() },
            sessionScopeProvider: { session.value }
        )

        viewModel.fetchFavoriteSongs()
        await favoritesLoader.waitUntilRequestCount(1)
        session.value = .authenticated(token: "new-token")
        viewModel.sessionDidChange()
        viewModel.fetchFavoriteSongs()
        await favoritesLoader.waitUntilRequestCount(2)

        await favoritesLoader.succeed(request: 1, with: [makeSong(id: "new")])
        await drainTasks()
        await favoritesLoader.succeed(request: 0, with: [makeSong(id: "old")])
        await drainTasks()

        #expect(viewModel.favoriteSongs.map(\.id) == ["new"])
        #expect(!viewModel.isLoadingFavorites)
    }

    @Test("Library navigation clears account-owned playlist routes on a session change")
    func libraryNavigationClearsSessionOwnedRoute() throws {
        let navigationState = LibraryNavigationState()
        navigationState.path.append(try makeUserPlaylist(id: "account-a-playlist").asPlaylist())
        #expect(navigationState.path.count == 1)

        navigationState.resetForSessionChange()

        #expect(navigationState.path.isEmpty)
    }

    @Test("Playlist detail clears Account A songs when Account B reload fails")
    func playlistDetailClearsOldSessionSongsWhenReplacementFails() async {
        let loader = ControlledSessionLoader<[Song]>()
        let viewModel = PlaylistDetailViewModel(
            playlistSongsLoader: { _ in try await loader.load() }
        )
        let accountASong = makeSong(id: "account-a-song")

        viewModel.reload(playlistID: "personal-playlist", fallback: [accountASong])
        await loader.waitUntilRequestCount(1)
        #expect(viewModel.songs?.map(\.id) == ["account-a-song"])

        viewModel.reloadForSessionChange(playlistID: "personal-playlist")
        #expect(viewModel.songs?.isEmpty == true)
        #expect(viewModel.isLoading)
        await loader.waitUntilRequestCount(2)

        await loader.fail(request: 1, with: URLError(.notConnectedToInternet))
        await drainTasks()
        #expect(viewModel.songs?.isEmpty == true)
        #expect(!viewModel.isLoading)
        #expect(
            viewModel.emptyStateMessage
                == "The playlist couldn't be loaded. Check your connection and try again."
        )

        await loader.succeed(request: 0, with: [makeSong(id: "late-account-a-song")])
        await drainTasks()
        #expect(viewModel.songs?.isEmpty == true)
        #expect(!viewModel.isLoading)
    }

    @Test("A failed public playlist reload preserves its fallback songs")
    func publicPlaylistFailurePreservesFallback() async {
        let loader = ControlledSessionLoader<[Song]>()
        let viewModel = PlaylistDetailViewModel(
            playlistSongsLoader: { _ in try await loader.load() }
        )

        viewModel.reload(
            playlistID: "public-playlist",
            fallback: [makeSong(id: "public-song")]
        )
        await loader.waitUntilRequestCount(1)
        await loader.fail(request: 0, with: URLError(.notConnectedToInternet))
        await drainTasks()

        #expect(viewModel.songs?.map(\.id) == ["public-song"])
        #expect(!viewModel.isLoading)
    }

    @Test("Playlist stores reject and sanitize session-owned playlists")
    func playlistStoresExcludeSessionOwnedPlaylists() throws {
        let suiteName = "UserSessionStateTests.PlaylistStores.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let publicPlaylist = makePlaylist(
            id: "public-playlist",
            songs: [makeSong(id: "public-song")]
        )
        let personalPlaylist = try makeUserPlaylist(id: "personal-playlist").asPlaylist()
        let favoritesPlaylist = makePlaylist(
            id: Playlist.favoritesID,
            songs: [makeSong(id: "account-a-favorite")]
        )
        let legacyData = try JSONEncoder().encode([
            personalPlaylist,
            favoritesPlaylist,
            publicPlaylist,
        ])
        defaults.set(legacyData, forKey: "nk.recentlyPlayed.playlists.v1")
        defaults.set(legacyData, forKey: "nk.savedPlaylists.v1")

        let recentlyPlayed = RecentlyPlayedStore(defaults: defaults)
        let saved = SavedPlaylistsStore(defaults: defaults)
        #expect(recentlyPlayed.playlists.map(\.id) == ["public-playlist"])
        #expect(saved.playlists.map(\.id) == ["public-playlist"])

        recentlyPlayed.record(personalPlaylist)
        recentlyPlayed.record(favoritesPlaylist)
        saved.add(personalPlaylist)
        saved.add(favoritesPlaylist)

        #expect(recentlyPlayed.playlists.map(\.id) == ["public-playlist"])
        #expect(saved.playlists.map(\.id) == ["public-playlist"])

        let restoredRecentlyPlayed = RecentlyPlayedStore(defaults: defaults)
        let restoredSaved = SavedPlaylistsStore(defaults: defaults)
        #expect(restoredRecentlyPlayed.playlists.map(\.id) == ["public-playlist"])
        #expect(restoredSaved.playlists.map(\.id) == ["public-playlist"])
    }

    @Test("Logout clears credentials and invokes the session reset boundary")
    func logoutInvokesSessionReset() throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("token", forKey: "nk.token")
        defaults.set("user-id", forKey: "nk.userId")
        defaults.set("User", forKey: "nk.username")
        defaults.set("avatar", forKey: "nk.avatar")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var resetCount = 0
        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: { resetCount += 1 }
        )
        #expect(auth.isLoggedIn)

        auth.logout()

        #expect(resetCount == 1)
        #expect(defaults.string(forKey: "nk.token") == nil)
        #expect(defaults.string(forKey: "nk.userId") == nil)
        #expect(defaults.string(forKey: "nk.username") == nil)
        #expect(defaults.string(forKey: "nk.avatar") == nil)
        #expect(!auth.isLoggedIn)
        #expect(auth.authToken == nil)
        #expect(auth.currentUserId == nil)
        #expect(auth.currentUsername == nil)
        #expect(auth.currentAvatar == nil)
    }

    @Test("Account views share app authentication state and allow injection")
    func accountViewAuthenticationOwnership() throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let injected = AuthManager(defaults: defaults, sessionStateResetter: {})
        let first = AccountView()
        let second = AccountView()

        #expect(first.auth === AuthManager.shared)
        #expect(second.auth === first.auth)
        #expect(AccountView(auth: injected).auth === injected)
    }

    @Test("Logout invalidates an in-flight sign-in")
    func logoutInvalidatesInFlightLogin() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenLoader = ControlledSessionLoader<String>()
        var resetCount = 0
        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: { resetCount += 1 },
            passwordTokenLoader: { _, _ in try await tokenLoader.load() }
        )

        let loginTask = Task {
            await auth.login(username: "Previous User", password: "password")
        }
        await tokenLoader.waitUntilRequestCount(1)

        auth.logout()
        await tokenLoader.succeed(request: 0, with: "stale-token")
        await loginTask.value

        #expect(resetCount == 1)
        #expect(defaults.string(forKey: "nk.token") == nil)
        #expect(!auth.isLoggedIn)
        #expect(!auth.isLoading)
        #expect(auth.authToken == nil)
    }

    @Test("An empty persisted token does not restore an authenticated session")
    func emptyPersistedTokenIsRejected() throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("", forKey: "nk.token")
        defaults.set("User", forKey: "nk.username")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let auth = AuthManager(defaults: defaults, sessionStateResetter: {})

        #expect(!auth.isLoggedIn)
        #expect(auth.authToken == nil)
        #expect(defaults.string(forKey: "nk.token") == nil)
        #expect(defaults.string(forKey: "nk.username") == nil)
    }

    @Test("A persisted token is normalized before restoring the session")
    func persistedTokenIsNormalized() throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("  persisted-token\n", forKey: "nk.token")
        defaults.set("User", forKey: "nk.username")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let auth = AuthManager(defaults: defaults, sessionStateResetter: {})

        #expect(auth.isLoggedIn)
        #expect(auth.authToken == "persisted-token")
        #expect(defaults.string(forKey: "nk.token") == "persisted-token")
    }

    @Test("Incomplete persisted credentials are purged")
    func incompletePersistedCredentialsArePurged() throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("stale-token", forKey: "nk.token")
        defaults.set("stale-user-id", forKey: "nk.userId")
        defaults.set("stale-avatar", forKey: "nk.avatar")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let auth = AuthManager(defaults: defaults, sessionStateResetter: {})

        #expect(!auth.isLoggedIn)
        #expect(auth.authToken == nil)
        #expect(defaults.string(forKey: "nk.token") == nil)
        #expect(defaults.string(forKey: "nk.userId") == nil)
        #expect(defaults.string(forKey: "nk.username") == nil)
        #expect(defaults.string(forKey: "nk.avatar") == nil)
    }

    @Test("Canceling authentication invalidates an in-flight sign-in")
    func cancelAuthenticationInvalidatesInFlightLogin() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenLoader = ControlledSessionLoader<String>()
        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: {},
            passwordTokenLoader: { _, _ in try await tokenLoader.load() }
        )

        let loginTask = Task {
            await auth.login(username: "Canceled User", password: "password")
        }
        await tokenLoader.waitUntilRequestCount(1)
        #expect(auth.activeAuthenticationMethod == .password)

        auth.cancelAuthentication()
        await tokenLoader.succeed(request: 0, with: "stale-token")
        await loginTask.value

        #expect(!auth.isLoggedIn)
        #expect(!auth.isLoading)
        #expect(auth.activeAuthenticationMethod == nil)
        #expect(auth.authToken == nil)
        #expect(defaults.string(forKey: "nk.token") == nil)
    }

    @Test("Canceling the sign-in task clears authentication progress")
    func taskCancellationInvalidatesInFlightLogin() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenLoader = ControlledSessionLoader<String>()
        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: {},
            passwordTokenLoader: { _, _ in try await tokenLoader.load() }
        )

        let loginTask = Task {
            await auth.login(username: "Canceled Task User", password: "password")
        }
        await tokenLoader.waitUntilRequestCount(1)
        #expect(auth.isLoading)
        #expect(auth.activeAuthenticationMethod == .password)

        loginTask.cancel()
        await tokenLoader.succeed(request: 0, with: "stale-token")
        await loginTask.value

        #expect(!auth.isLoggedIn)
        #expect(!auth.isLoading)
        #expect(auth.activeAuthenticationMethod == nil)
        #expect(auth.authToken == nil)
        #expect(defaults.string(forKey: "nk.token") == nil)
    }

    @Test("A pre-canceled sign-in task does not supersede the active attempt")
    func preCanceledTaskDoesNotSupersedeActiveLogin() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenLoader = ControlledSessionLoader<String>()
        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: {},
            passwordTokenLoader: { _, _ in try await tokenLoader.load() }
        )

        let activeLoginTask = Task {
            await auth.login(username: "Active User", password: "password")
        }
        await tokenLoader.waitUntilRequestCount(1)

        let canceledLoginTask = Task {
            await auth.login(username: "Canceled User", password: "password")
        }
        canceledLoginTask.cancel()
        await canceledLoginTask.value

        let requestCount = await tokenLoader.requestCount
        #expect(requestCount == 1)
        #expect(auth.isLoading)
        #expect(auth.activeAuthenticationMethod == .password)

        await tokenLoader.succeed(request: 0, with: "active-token")
        await activeLoginTask.value

        #expect(auth.isLoggedIn)
        #expect(auth.currentUsername == "Active User")
        #expect(auth.authToken == "active-token")
    }

    @Test("Password sign-in rejects a whitespace-only token")
    func passwordLoginRejectsWhitespaceToken() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: {},
            passwordTokenLoader: { _, _ in "  \n" }
        )

        await auth.login(username: "User", password: "password")

        #expect(!auth.isLoggedIn)
        #expect(!auth.isLoading)
        #expect(auth.activeAuthenticationMethod == nil)
        #expect(auth.authToken == nil)
        #expect(auth.errorMessage == "Unexpected server response")
        #expect(defaults.string(forKey: "nk.token") == nil)
    }

    @Test("Password sign-in normalizes a padded token before persisting it")
    func passwordLoginNormalizesToken() async throws {
        let suiteName = "UserSessionStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let auth = AuthManager(
            defaults: defaults,
            sessionStateResetter: {},
            passwordTokenLoader: { _, _ in "  normalized-token\n" }
        )

        await auth.login(username: "User", password: "password")

        #expect(auth.isLoggedIn)
        #expect(auth.authToken == "normalized-token")
        #expect(defaults.string(forKey: "nk.token") == "normalized-token")
    }

    @Test("The NK token exchange rejects a non-success response")
    func nkTokenExchangeRejectsHTTPFailure() {
        let body = "temporarily unavailable"

        #expect(throws: AuthManager.AuthError.http(503, body)) {
            try AuthManager.parseNKTokenExchangeResponse(
                data: Data(body.utf8),
                statusCode: 503
            )
        }
    }

    @Test("The NK token exchange rejects malformed and empty token payloads")
    func nkTokenExchangeRejectsInvalidPayloads() {
        let invalidPayloads = [
            "",
            "   \n",
            "{}",
            "{\"token\":\"\"}",
            "{\"accessToken\":\"   \"}",
            "{\"token\":}",
            "[]",
            "\"\"",
        ]

        for payload in invalidPayloads {
            #expect(throws: AuthManager.AuthError.parse) {
                try AuthManager.parseNKTokenExchangeResponse(
                    data: Data(payload.utf8),
                    statusCode: 200
                )
            }
        }
    }

    @Test("The NK token exchange accepts supported response formats")
    func nkTokenExchangeAcceptsSupportedPayloads() throws {
        let payloads = [
            ("{\"token\":\"nk-json-token\"}", "nk-json-token"),
            ("{\"accessToken\":\"nk-legacy-token\"}", "nk-legacy-token"),
            ("  nk-plain-token\n", "nk-plain-token"),
            ("\"nk-quoted-token\"", "nk-quoted-token"),
        ]

        for (payload, expectedToken) in payloads {
            let token = try AuthManager.parseNKTokenExchangeResponse(
                data: Data(payload.utf8),
                statusCode: 200
            )

            #expect(token == expectedToken)
        }
    }

    private func makeUserPlaylist(id: String) throws -> UserPlaylist {
        let data = Data(
            """
            {
              "id": "\(id)",
              "name": "\(id)",
              "songCount": 0,
              "playCount": 0,
              "editable": true,
              "deletable": true,
              "isPublic": false,
              "isSetList": false
            }
            """.utf8
        )
        return try JSONDecoder().decode(UserPlaylist.self, from: data)
    }

    private func makePlaylist(
        id: String,
        songs: [Song]? = nil,
        isPersonal: Bool = false
    ) -> Playlist {
        Playlist(
            id: id,
            name: id,
            songCount: songs?.count ?? 0,
            mosaicMedia: nil,
            songListDTOs: songs,
            isPersonal: isPersonal
        )
    }

    private func makeSong(id: String) -> Song {
        Song(
            id: id,
            title: id,
            duration: 60,
            absolutePath: "/audio/\(id).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )
    }

    private func drainTasks() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }
}
