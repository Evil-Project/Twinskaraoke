import Foundation
import Testing
@testable import Twinskaraoke

/// Stands in for the setlist requests. Page requests wait until the test
/// answers them, so a test controls the order responses land in.
@MainActor
private final class FakeSetlistService {
    struct PageCall: Equatable {
        let filter: SetlistsViewModel.Filter
        let startIndex: Int
    }

    private(set) var pageCalls: [PageCall] = []
    private var pending: [Int: CheckedContinuation<SetlistsViewModel.Page, any Error>] = [:]
    var latestCalls = 0

    var service: SetlistsViewModel.Service {
        SetlistsViewModel.Service(
            page: { filter, startIndex, _ in
                let index = self.pageCalls.count
                self.pageCalls.append(PageCall(filter: filter, startIndex: startIndex))
                return try await withCheckedThrowingContinuation { self.pending[index] = $0 }
            },
            latest: {
                self.latestCalls += 1
                return Self.setlist("latest")
            },
            stats: { SetlistStats(totalCount: 3, years: [2025, 2026]) }
        )
    }

    static func setlist(_ id: String) -> KaraokeSetlist {
        KaraokeSetlist(
            playlist: Playlist(id: id, name: id, songCount: 0, mosaicMedia: nil, songListDTOs: nil),
            streamDay: nil,
            totalDuration: nil
        )
    }

    func waitForPageCalls(_ count: Int) async {
        while pageCalls.count < count || pending[count - 1] == nil { await Task.yield() }
    }

    /// `sourceCount` above `ids.count` stands for entries that failed to decode.
    func answer(_ call: Int, ids: [String], sourceCount: Int? = nil) {
        let page = SetlistsViewModel.Page(setlists: ids.map(Self.setlist), sourceCount: sourceCount ?? ids.count)
        pending.removeValue(forKey: call)?.resume(returning: page)
    }

    func fail(_ call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: URLError(.notConnectedToInternet))
    }
}

@MainActor
@Suite("Setlists view model")
struct SetlistsViewModelTests {
    private func settle(_ model: SetlistsViewModel) async {
        while model.isLoading || model.isLoadingMore { await Task.yield() }
    }

    /// Waits until `condition` holds, for requests that never come when the
    /// code is broken: it gives up after `timeout` so the test fails instead
    /// of hanging, and it waits on the condition rather than a number of
    /// turns, so a busy machine can't fail it early.
    private func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test("The first load fetches the latest setlist, the years and page one, once")
    func loadsOnce() async {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)
        fake.answer(0, ids: ["a", "b"])
        await settle(model)
        while model.latest == nil || model.years.isEmpty { await Task.yield() }

        #expect(fake.pageCalls == [.init(filter: .init(), startIndex: 0)])
        #expect(fake.latestCalls == 1)
        #expect(model.latest?.id == "latest")
        #expect(model.years == [2026, 2025])
        #expect(model.setlists.map(\.id) == ["a", "b"])
    }

    @Test("Scrolling to the end loads the next page until a short page")
    func pages() async throws {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)
        // One of the two entries failed to decode; the page is still full.
        fake.answer(0, ids: ["a"], sourceCount: 2)
        await settle(model)

        model.loadMoreIfNeeded(current: try #require(model.setlists.last))
        await fake.waitForPageCalls(2)
        #expect(fake.pageCalls[1].startIndex == 2)
        fake.answer(1, ids: ["a", "c"])
        await settle(model)
        #expect(model.setlists.map(\.id) == ["a", "c"])

        model.loadMoreIfNeeded(current: try #require(model.setlists.last))
        await fake.waitForPageCalls(3)
        #expect(fake.pageCalls[2].startIndex == 4)
        fake.answer(2, ids: ["d"])
        await settle(model)
        #expect(model.setlists.map(\.id) == ["a", "c", "d"])

        model.loadMoreIfNeeded(current: try #require(model.setlists.last))
        #expect(fake.pageCalls.count == 3)
    }

    @Test("Choosing a year clears the list and drops a late page from before")
    func changingYearDropsStalePage() async {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)

        model.selectYear(2025)
        #expect(model.setlists.isEmpty)
        await fake.waitForPageCalls(2)
        #expect(fake.pageCalls[1] == .init(filter: .init(year: 2025), startIndex: 0))
        fake.answer(1, ids: ["y2025"])
        await settle(model)
        fake.answer(0, ids: ["all-years"])
        for _ in 0 ..< 20 { await Task.yield() }

        #expect(model.setlists.map(\.id) == ["y2025"])
        #expect(model.filter.year == 2025)
    }

    @Test("Search keeps the chosen year and ignores surrounding spaces")
    func searchWithinYear() async {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        model.selectYear(2025)
        await model.search("  christmas ")
        await fake.waitForPageCalls(3)
        #expect(fake.pageCalls[2] == .init(filter: .init(year: 2025, search: "christmas"), startIndex: 0))

        await model.search("christmas")
        #expect(fake.pageCalls.count == 3)
        for call in 0 ..< 3 {
            fake.answer(call, ids: [])
        }
        await settle(model)
    }

    @Test("A failed refresh keeps the list; a failed new filter clears it and can retry")
    func failures() async {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)
        fake.answer(0, ids: ["a"])
        await settle(model)

        let refresh = Task { await model.refresh() }
        await fake.waitForPageCalls(2)
        fake.fail(1)
        await refresh.value
        #expect(model.setlists.map(\.id) == ["a"])
        #expect(!model.loadFailed)

        let search = Task { await model.search("zzz") }
        await fake.waitForPageCalls(3)
        fake.fail(2)
        await search.value
        await settle(model)
        #expect(model.setlists.isEmpty)
        #expect(model.loadFailed)

        model.retry()
        #expect(!model.loadFailed)
        await fake.waitForPageCalls(4)
        #expect(fake.pageCalls[3] == .init(filter: .init(search: "zzz"), startIndex: 0))
        fake.answer(3, ids: ["zzz"])
        await settle(model)
        #expect(model.setlists.map(\.id) == ["zzz"])
    }

    @Test("A failed refresh keeps paging where it was")
    func failedRefreshKeepsPaging() async throws {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)
        fake.answer(0, ids: ["a", "b"])
        await settle(model)
        model.loadMoreIfNeeded(current: try #require(model.setlists.last))
        await fake.waitForPageCalls(2)
        fake.answer(1, ids: ["c", "d"])
        await settle(model)

        let refresh = Task { await model.refresh() }
        await fake.waitForPageCalls(3)
        fake.fail(2)
        await refresh.value
        #expect(model.setlists.map(\.id) == ["a", "b", "c", "d"])

        model.loadMoreIfNeeded(current: try #require(model.setlists.last))
        let askedForMore = await eventually { fake.pageCalls.count == 4 }
        try #require(askedForMore, "Scrolling to the end asked for nothing after the failed refresh.")
        #expect(fake.pageCalls[3].startIndex == 4)
        fake.answer(3, ids: [])
        await settle(model)
    }

    @Test("A full page with nothing to show loads the next one by itself")
    func skipsUnusablePages() async throws {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        await fake.waitForPageCalls(1)
        // Both entries failed to decode, so no row appears to ask for more.
        fake.answer(0, ids: [], sourceCount: 2)
        let loadedNext = await eventually { fake.pageCalls.count == 2 }
        try #require(loadedNext, "The empty page left the list stuck.")
        #expect(fake.pageCalls[1].startIndex == 2)
        #expect(model.isLoading)
        fake.answer(1, ids: ["c"])
        await settle(model)
        #expect(model.setlists.map(\.id) == ["c"])
        #expect(!model.loadFailed)
    }

    @Test("Pages that keep adding nothing stop after three, instead of loading forever")
    func stopsAfterUnusablePagesInARow() async throws {
        let fake = FakeSetlistService()
        let model = SetlistsViewModel(service: fake.service, pageSize: 2, searchDelay: .zero)
        model.loadIfNeeded()
        // A server that ignored `startIndex` would answer every page like this.
        for call in 0 ..< 4 {
            await fake.waitForPageCalls(call + 1)
            fake.answer(call, ids: [], sourceCount: 2)
        }
        let askedAgain = await eventually(timeout: .milliseconds(300)) { fake.pageCalls.count > 4 }
        #expect(!askedAgain, "Kept loading after three pages in a row added nothing.")
        if askedAgain {
            fake.answer(4, ids: [])
        }
        await settle(model)
        #expect(model.loadFailed)
        #expect(model.setlists.isEmpty)

        model.retry()
        await fake.waitForPageCalls(fake.pageCalls.count + 1)
        #expect(fake.pageCalls.last?.startIndex == 0)
        fake.answer(fake.pageCalls.count - 1, ids: ["a"])
        await settle(model)
        #expect(model.setlists.map(\.id) == ["a"])
    }
}
