import Foundation
import Testing
@testable import Twinskaraoke

/// Home's requests, each answered at once, failed, or held until the test
/// lets it through. What a request returns is decided when it's made, so a
/// held response still carries what was current then.
@MainActor
private final class StubHomeRequests {
    enum Mode {
        case answer
        case fail(URLError.Code)
        case hold
    }

    var mode: Mode = .answer
    var suggestionsMode: Mode?
    var account: HomeAccount? = .signedIn("account-a")
    var trendingSongs = StubHomeRequests.songs("fresh-trending", count: 3)
    var releaseSongs = StubHomeRequests.songs("fresh-release", count: 3)
    var suggestionSongs = StubHomeRequests.songs("fresh-made", count: 3)
    var picks = [UITestFixtures.playlist(
        id: "fresh-pick",
        name: "Fresh Pick",
        songs: StubHomeRequests.songs("fresh-pick", count: 2)
    )]
    private(set) var trendingCalls = 0
    private(set) var suggestionCalls = 0
    private(set) var setlistPageCalls = 0
    private(set) var publicPlaylistCalls = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    static func songs(_ prefix: String, count: Int) -> [Song] {
        (0 ..< count).map { UITestFixtures.song(id: "\(prefix)-\($0)", title: "Song \(prefix) \($0)", artist: "Artist") }
    }

    var requests: HomeViewModel.Requests {
        HomeViewModel.Requests(
            trending: {
                self.trendingCalls += 1
                return try await self.respond(self.mode, self.trendingSongs)
            },
            suggestions: {
                self.suggestionCalls += 1
                return try await self.respond(self.suggestionsMode ?? self.mode, self.suggestionSongs)
            },
            releases: { try await self.respond(self.mode, self.releaseSongs) },
            setlists: { _, _ in
                self.setlistPageCalls += 1
                return try await self.respond(self.mode, self.picks)
            },
            publicPlaylists: { _, _ in
                self.publicPlaylistCalls += 1
                return try await self.respond(self.mode, [])
            },
            latestSetlist: {
                try await self.respond(self.mode, KaraokeSetlist(
                    playlist: UITestFixtures.playlist(id: "fresh-setlist", name: "Fresh", songs: self.trendingSongs),
                    streamDay: nil,
                    totalDuration: nil
                ))
            }
        )
    }

    var accountIdentity: @Sendable () async -> HomeAccount? {
        { await self.account }
    }

    func releaseHeld() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    private func respond<T>(_ mode: Mode, _ value: T) async throws -> T {
        switch mode {
        case .answer:
            return value
        case let .fail(code):
            throw URLError(code)
        case .hold:
            await withCheckedContinuation { held.append($0) }
            return value
        }
    }
}

/// Records every suggestions save, so a test can tell nothing was written.
@MainActor
private final class SuggestionSaves {
    private(set) var saves: [(account: String, ids: [String])] = []

    func record(_ account: String, _ snapshot: HomeSuggestionsSnapshot) {
        saves.append((account, snapshot.songs.map(\.id)))
    }
}

/// Home and New fall back to what was saved on the device only when a load
/// got nothing, and the saved copy only ever holds content that loaded.
@MainActor
@Suite("Home feed cache loading")
struct HomeFeedCacheLoadTests {
    private let saves = SuggestionSaves()
    private let base = HomeFeedStore.inMemory()

    private var store: HomeFeedStore {
        let memory = base
        let saves = saves
        var store = memory
        store.saveSuggestions = { account, snapshot in
            await saves.record(account, snapshot)
            await memory.saveSuggestions(account, snapshot)
        }
        return store
    }

    private func model(_ stub: StubHomeRequests) -> HomeViewModel {
        HomeViewModel(requests: stub.requests, store: store, accountIdentity: stub.accountIdentity)
    }

    private func fillCache() async {
        await base.savePublic(HomeFeedSnapshot(
            trending: StubHomeRequests.songs("saved-trending", count: 2),
            newReleases: StubHomeRequests.songs("saved-release", count: 2),
            topPicks: [UITestFixtures.playlist(
                id: "saved-pick",
                name: "Saved Pick",
                songs: StubHomeRequests.songs("saved-pick", count: 2)
            )],
            topPicksSource: .publicPlaylists,
            latestSetlist: CachedSetlist(KaraokeSetlist(
                playlist: UITestFixtures.playlist(
                    id: "saved-setlist",
                    name: "Saved",
                    songs: StubHomeRequests.songs("saved-set", count: 2)
                ),
                streamDay: nil,
                totalDuration: nil
            ))
        ))
        await base.saveSuggestions(
            "account-a",
            HomeSuggestionsSnapshot(songs: StubHomeRequests.songs("saved-made", count: 2))
        )
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while await !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Lets saves and reads that were started settle before checking that
    /// something did not happen.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    private func ids(_ songs: [Song]?) -> [String]? {
        songs?.map(\.id)
    }

    @Test("A load that succeeds saves what it loaded")
    func freshDataIsSavedAfterALoad() async throws {
        let stub = StubHomeRequests()
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil {
            let saved = await base.loadPublic()
            return saved?.latestSetlist != nil && saved?.trending != nil
        }

        let saved = try #require(await base.loadPublic())
        #expect(ids(saved.trending) == ids(stub.trendingSongs))
        #expect(ids(saved.newReleases) == ids(stub.releaseSongs))
        #expect(saved.topPicks?.map(\.id) == ["fresh-pick"])
        #expect(saved.topPicksSource == .setlists)
        #expect(saved.latestSetlist?.setlist.id == "fresh-setlist")
        #expect(!model.isShowingSavedContent)
    }

    @Test("Online, Home shows its skeleton, not the saved shelves, while loading")
    func onlineLoadDoesNotShowCachedShelvesFirst() async {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .hold
        let model = model(stub)

        model.fetchHomeData()
        await settle()
        #expect(model.isLoading)
        #expect(model.trending.isEmpty)
        #expect(model.suggestions.isEmpty)
        #expect(model.recentPlaylists.isEmpty)
        #expect(!model.isShowingSavedContent)

        stub.releaseHeld()
        await waitUntil { !model.isLoading }
        #expect(ids(model.trending) == ids(stub.trendingSongs))
        #expect(!model.isShowingSavedContent)
    }

    @Test("Offline with a saved copy, Home and New show it instead of the error")
    func offlineWithCacheShowsSavedContentNotError() async {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil { model.isShowingSavedContent && !model.isLoading }

        #expect(model.isShowingSavedContent)
        #expect(!model.homeIsEmpty)
        #expect(!model.newIsEmpty)
        #expect(ids(model.trending) == ["saved-trending-0", "saved-trending-1"])
        #expect(ids(model.newReleases) == ["saved-release-0", "saved-release-1"])
        #expect(model.latestSingle?.id == "saved-release-0")
        #expect(model.recentPlaylists.map(\.id) == ["saved-pick"])
        #expect(ids(model.suggestions) == ["saved-made-0", "saved-made-1"])
        #expect(model.latestSetlist?.id == "saved-setlist")
    }

    @Test("Offline with nothing saved, the error shows as before")
    func offlineWithoutCacheStillShowsError() async {
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil { model.hasFinishedLoading && !model.isLoading }
        await settle()

        #expect(model.homeIsEmpty)
        #expect(model.newIsEmpty)
        #expect(!model.isShowingSavedContent)
    }

    @Test("A refresh that fails keeps the saved copy as it was")
    func failedRefreshDoesNotOverwriteCache() async throws {
        let stub = StubHomeRequests()
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { await base.loadPublic()?.trending != nil }

        stub.mode = .fail(.notConnectedToInternet)
        await model.refreshHomeData()
        await settle()

        let saved = try #require(await base.loadPublic())
        #expect(ids(saved.trending) == ids(stub.trendingSongs))
        #expect(ids(saved.newReleases) == ids(stub.releaseSongs))
        #expect(saves.saves.count == 1)
        // The shelves already on screen stay; nothing came from the device.
        #expect(!model.isShowingSavedContent)
        #expect(ids(model.trending) == ids(stub.trendingSongs))
    }

    @Test("When some shelves load, the rest aren't filled from the saved copy")
    func partialFailureDoesNotShowSavedNotice() async throws {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = HomeViewModel(
            requests: HomeViewModel.Requests(
                trending: { StubHomeRequests.songs("fresh-trending", count: 3) },
                suggestions: { throw URLError(.timedOut) },
                releases: { throw URLError(.timedOut) },
                setlists: { _, _ in throw URLError(.timedOut) },
                publicPlaylists: { _, _ in throw URLError(.timedOut) },
                latestSetlist: { throw URLError(.timedOut) }
            ),
            store: store,
            accountIdentity: stub.accountIdentity
        )

        model.fetchHomeData()
        await waitUntil { await base.loadPublic()?.trending?.first?.id == "fresh-trending-0" }
        await settle()

        #expect(!model.isShowingSavedContent)
        #expect(model.newReleases.isEmpty)
        #expect(model.recentPlaylists.isEmpty)
        let saved = try #require(await base.loadPublic())
        #expect(ids(saved.newReleases) == ["saved-release-0", "saved-release-1"])
        #expect(saved.topPicks?.map(\.id) == ["saved-pick"])
    }

    @Test("A load that a newer one replaced writes nothing")
    func supersededLoadDoesNotWriteCache() async {
        let stub = StubHomeRequests()
        stub.mode = .hold
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { stub.trendingCalls == 1 }

        stub.mode = .fail(.notConnectedToInternet)
        model.fetchHomeData(force: true)
        await waitUntil { stub.trendingCalls == 2 }
        stub.releaseHeld()
        await waitUntil { model.hasFinishedLoading && !model.isLoading }
        await settle()

        #expect(await base.loadPublic() == nil)
        #expect(saves.saves.isEmpty)
        #expect(model.trending.isEmpty)
    }

    @Test("Cancelled requests never clear or overwrite the saved copy")
    func urlErrorCancelledDoesNotClearCache() async throws {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.cancelled)
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil { model.hasFinishedLoading && !model.isLoading }
        await settle()

        let saved = try #require(await base.loadPublic())
        #expect(ids(saved.trending) == ["saved-trending-0", "saved-trending-1"])
        #expect(saved.latestSetlist?.setlist.id == "saved-setlist")
        #expect(ids(await base.loadSuggestions("account-a")?.songs) == ["saved-made-0", "saved-made-1"])
        #expect(saves.saves.isEmpty)
    }

    @Test("Made for You is saved under the account that loaded it")
    func suggestionsAreSavedUnderTheAccountThatLoadedThem() async {
        let stub = StubHomeRequests()
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil { await base.loadSuggestions("account-a") != nil }

        #expect(saves.saves.map(\.account) == ["account-a"])
        #expect(ids(await base.loadSuggestions("account-a")?.songs) == ids(stub.suggestionSongs))
        #expect(await base.loadSuggestions("account-b") == nil)
    }

    @Test("Signing in as someone else drops Made for You and keeps the public shelves")
    func accountChangeDropsMadeForYouAndKeepsPublicShelves() async {
        let stub = StubHomeRequests()
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { !model.isLoading && !model.suggestions.isEmpty }

        stub.account = .signedIn("account-b")
        stub.suggestionSongs = StubHomeRequests.songs("made-b", count: 2)
        stub.mode = .hold
        NotificationCenter.default.post(name: WatchSessionLink.sessionChanged, object: nil)
        await waitUntil { stub.suggestionCalls == 2 }

        #expect(model.suggestions.isEmpty)
        #expect(ids(model.trending) == ids(stub.trendingSongs))
        #expect(!model.isLoading)

        stub.releaseHeld()
        await waitUntil { !model.suggestions.isEmpty }
        #expect(ids(model.suggestions) == ["made-b-0", "made-b-1"])
    }

    @Test("A response for the previous account is dropped, and never saved under the new one")
    func responseFromPreviousAccountIsDiscarded() async {
        let stub = StubHomeRequests()
        stub.mode = .hold
        stub.suggestionSongs = StubHomeRequests.songs("made-a", count: 2)
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { stub.suggestionCalls == 1 }

        stub.account = .signedIn("account-b")
        stub.suggestionSongs = StubHomeRequests.songs("made-b", count: 2)
        await model.accountMayHaveChanged()
        await waitUntil { stub.suggestionCalls == 2 }
        stub.releaseHeld()
        await waitUntil { !model.suggestions.isEmpty && !saves.saves.isEmpty }
        await settle()

        #expect(ids(model.suggestions) == ["made-b-0", "made-b-1"])
        #expect(saves.saves.count == 1)
        #expect(saves.saves.first?.account == "account-b")
        #expect(saves.saves.first?.ids == ["made-b-0", "made-b-1"])
    }

    @Test("Signed out, Made for You is never saved")
    func signedOutNeverWritesSuggestions() async {
        let stub = StubHomeRequests()
        stub.account = .signedOut
        let model = model(stub)

        model.fetchHomeData()
        await waitUntil { await base.loadPublic()?.trending != nil }
        await settle()

        #expect(saves.saves.isEmpty)
        #expect(!model.suggestions.isEmpty)
    }

    @Test("Coming back to the app retries while the saved copy is shown")
    func activationRetriesWhileShowingSavedContent() async {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { model.isShowingSavedContent && !model.isLoading }
        #expect(model.isShowingSavedContent)

        model.retryIfLoadFailed()
        await waitUntil { stub.trendingCalls == 2 }
        #expect(stub.trendingCalls == 2)
        await waitUntil { !model.isLoading }
        await settle()
        // Still offline: the saved copy stays, and so does the notice.
        #expect(model.isShowingSavedContent)
        #expect(ids(model.trending) == ["saved-trending-0", "saved-trending-1"])

        // Appearing again also retries.
        model.fetchHomeData()
        await waitUntil { stub.trendingCalls == 3 }
        #expect(stub.trendingCalls == 3)
    }

    @Test("A retry that loads replaces the saved copy and clears the notice")
    func successfulRetryClearsSavedContentFlag() async {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { model.isShowingSavedContent && !model.isLoading }
        #expect(model.isShowingSavedContent)

        stub.mode = .answer
        model.retryIfLoadFailed()
        await waitUntil { !model.isShowingSavedContent }

        #expect(!model.isShowingSavedContent)
        #expect(ids(model.trending) == ids(stub.trendingSongs))
        #expect(ids(model.newReleases) == ids(stub.releaseSongs))
        #expect(model.recentPlaylists.map(\.id) == ["fresh-pick"])
        #expect(ids(model.suggestions) == ids(stub.suggestionSongs))
    }

    @Test("Saved top picks don't page")
    func cachedTopPicksDoNotPage() async throws {
        await fillCache()
        let stub = StubHomeRequests()
        stub.mode = .fail(.notConnectedToInternet)
        let model = model(stub)
        model.fetchHomeData()
        await waitUntil { model.isShowingSavedContent && !model.isLoading }
        try #require(model.isShowingSavedContent)
        let setlistCalls = stub.setlistPageCalls
        let publicCalls = stub.publicPlaylistCalls

        #expect(!model.canLoadMoreTopPicks)
        model.loadMoreTopPicksIfNeeded(current: try #require(model.recentPlaylists.last))
        await settle()

        #expect(stub.setlistPageCalls == setlistCalls)
        #expect(stub.publicPlaylistCalls == publicCalls)
        #expect(!model.isLoadingMoreTopPicks)
    }
}
