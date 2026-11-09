import Foundation
import Testing
@testable import Twinskaraoke

/// Stands in for Home's requests. The latest setlist waits until the test
/// answers it, unless `answersSetlistAtOnce` is set.
@MainActor
private final class FakeHomeRequests {
    static let songs = (1 ... 3).map {
        UITestFixtures.song(id: "song-\($0)", title: "Song \($0)", artist: "Artist")
    }

    var feedsFail = false
    var answersSetlistAtOnce = false
    var setlistSongs = songs
    private(set) var trendingCalls = 0
    private var pendingSetlist: CheckedContinuation<KaraokeSetlist, any Error>?

    var requests: HomeViewModel.Requests {
        HomeViewModel.Requests(
            trending: {
                self.trendingCalls += 1
                return try self.feed()
            },
            suggestions: { try self.feed() },
            releases: { try self.feed() },
            setlists: { _, _ in
                if self.feedsFail { throw URLError(.notConnectedToInternet) }
                return []
            },
            publicPlaylists: { _, _ in
                if self.feedsFail { throw URLError(.notConnectedToInternet) }
                return []
            },
            latestSetlist: {
                if self.answersSetlistAtOnce { return self.setlist }
                return try await withCheckedThrowingContinuation { self.pendingSetlist = $0 }
            }
        )
    }

    private var setlist: KaraokeSetlist {
        KaraokeSetlist(
            playlist: UITestFixtures.playlist(id: "latest", name: "Latest", songs: setlistSongs),
            streamDay: nil,
            totalDuration: nil
        )
    }

    private func feed() throws -> [Song] {
        if feedsFail { throw URLError(.notConnectedToInternet) }
        return Self.songs
    }

    func answerSetlist() {
        pendingSetlist?.resume(returning: setlist)
        pendingSetlist = nil
    }
}

/// New's latest-stream card is extra: its request must not hold Home and New
/// on their skeletons, and on its own it is enough for New to show.
@MainActor
@Suite("Home latest setlist loading")
struct HomeLatestSetlistLoadTests {
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Home and New finish loading without waiting for the latest setlist")
    func feedsDoNotWaitForTheSetlist() async {
        let fake = FakeHomeRequests()
        let model = HomeViewModel(requests: fake.requests)

        model.fetchHomeData()
        await waitUntil { !model.isLoading }

        #expect(!model.isLoading)
        #expect(model.trending == FakeHomeRequests.songs)
        #expect(model.latestSetlist == nil)

        fake.answerSetlist()
        await waitUntil { model.latestSetlist != nil }
        #expect(model.latestSetlist?.id == "latest")
    }

    @Test("New shows the latest setlist when every other feed failed; Home still shows its error")
    func setlistAloneFillsNew() async {
        let fake = FakeHomeRequests()
        fake.feedsFail = true
        fake.answersSetlistAtOnce = true
        let model = HomeViewModel(requests: fake.requests)

        model.fetchHomeData()
        await waitUntil { model.hasFinishedLoading && model.latestSetlist != nil }

        #expect(!model.newIsEmpty)
        #expect(model.homeIsEmpty)
    }

    @Test("A setlist without songs doesn't count as something to show")
    func emptySetlistLeavesNewEmpty() async {
        let fake = FakeHomeRequests()
        fake.feedsFail = true
        fake.answersSetlistAtOnce = true
        fake.setlistSongs = []
        let model = HomeViewModel(requests: fake.requests)

        model.fetchHomeData()
        await waitUntil { model.hasFinishedLoading && model.latestSetlist != nil }

        #expect(model.playableLatestSetlist == nil)
        #expect(model.newIsEmpty)
    }

    @Test("A load that left Home empty is retried, even when the setlist loaded")
    func emptyHomeIsRetried() async {
        let fake = FakeHomeRequests()
        fake.feedsFail = true
        fake.answersSetlistAtOnce = true
        let model = HomeViewModel(requests: fake.requests)
        model.fetchHomeData()
        await waitUntil { model.hasFinishedLoading && model.latestSetlist != nil }

        model.retryIfLoadFailed()
        await waitUntil { fake.trendingCalls == 2 }

        #expect(fake.trendingCalls == 2)
    }
}
