import Foundation
import Observation

/// State for the Karaoke Setlists screen: the latest stream's setlist, the
/// years to filter by, and the setlists for the chosen year and search, loaded
/// a page at a time.
@MainActor
@Observable
final class SetlistsViewModel {
    /// The year and search text the list is loaded for.
    struct Filter: Equatable {
        /// Nil means every year.
        var year: Int?
        var search = ""
    }

    /// The requests behind the screen, replaced in tests.
    struct Service {
        var page: @MainActor (_ filter: Filter, _ startIndex: Int, _ pageSize: Int) async throws
            -> LossyArray<KaraokeSetlist>
        var latest: @MainActor () async throws -> KaraokeSetlist
        var stats: @MainActor () async throws -> SetlistStats

        static var live: Service {
            Service(
                page: { filter, startIndex, pageSize in
                    try await KaraokeAPIClient.setlists(
                        startIndex: startIndex,
                        pageSize: pageSize,
                        year: filter.year,
                        search: filter.search
                    )
                },
                latest: { try await KaraokeAPIClient.latestSetlist() },
                stats: { try await KaraokeAPIClient.setlistStats() }
            )
        }
    }

    private(set) var latest: KaraokeSetlist?
    /// Years with setlists, newest first.
    private(set) var years: [Int] = []
    private(set) var setlists: [KaraokeSetlist] = []
    private(set) var filter = Filter()
    /// The first page for `filter` is on its way.
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    /// The first page for `filter` failed and there is nothing to show.
    private(set) var loadFailed = false

    @ObservationIgnored private let service: Service
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let searchDelay: Duration
    @ObservationIgnored private var hasLoaded = false
    /// The filter `setlists` were loaded for.
    @ObservationIgnored private var shownFilter = Filter()
    @ObservationIgnored private var nextOffset = 0
    @ObservationIgnored private var canLoadMore = false
    /// Bumped whenever the list starts over, so a page for an earlier filter
    /// is dropped when it lands late.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var headerTask: Task<Void, Never>?

    init(service: Service = .live, pageSize: Int = 25, searchDelay: Duration = .milliseconds(300)) {
        self.service = service
        self.pageSize = pageSize
        self.searchDelay = searchDelay
    }

    isolated deinit {
        pageTask?.cancel()
        headerTask?.cancel()
    }

    /// Loads the latest setlist, the years and the first page, once.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadHeader()
        reload()
    }

    /// Pull to refresh. What's on screen stays until it's replaced.
    func refresh() async {
        loadHeader()
        reload()
        await headerTask?.value
        await pageTask?.value
    }

    func retry() {
        if latest == nil || years.isEmpty { loadHeader() }
        reload()
    }

    func selectYear(_ year: Int?) {
        guard year != filter.year else { return }
        filter.year = year
        // The other year's setlists must not show under this one.
        setlists = []
        reload()
    }

    /// Runs from the view's `task(id:)`, which cancels it when the text
    /// changes again; that is the debounce. Results for the old text stay on
    /// screen until the new ones arrive, so typing doesn't flash the list.
    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != filter.search else { return }
        do {
            try await Task.sleep(for: searchDelay)
        } catch {
            return
        }
        filter.search = query
        reload()
    }

    func loadMoreIfNeeded(current setlist: KaraokeSetlist) {
        guard canLoadMore, !isLoading, !isLoadingMore,
              let index = setlists.firstIndex(where: { $0.id == setlist.id }),
              index >= setlists.count - 4
        else { return }
        isLoadingMore = true
        loadPage(startIndex: nextOffset)
    }

    private func loadHeader() {
        headerTask?.cancel()
        let service = service
        headerTask = Task { [weak self] in
            async let latest = try? service.latest()
            async let stats = try? service.stats()
            let (loadedLatest, loadedStats) = await (latest, stats)
            guard !Task.isCancelled, let self else { return }
            // A failed refresh keeps what's already there.
            if let loadedLatest { self.latest = loadedLatest }
            if let loadedStats { years = loadedStats.years }
        }
    }

    private func reload() {
        generation += 1
        pageTask?.cancel()
        nextOffset = 0
        canLoadMore = false
        isLoadingMore = false
        loadFailed = false
        isLoading = true
        loadPage(startIndex: 0)
    }

    private func loadPage(startIndex: Int) {
        let generation = generation
        let filter = filter
        let service = service
        let pageSize = pageSize
        pageTask = Task { [weak self] in
            let result: Result<LossyArray<KaraokeSetlist>, any Error>
            do {
                result = try await .success(service.page(filter, startIndex, pageSize))
            } catch {
                result = .failure(error)
            }
            guard let self, self.generation == generation else { return }
            apply(result, for: filter, startIndex: startIndex)
        }
    }

    private func apply(_ result: Result<LossyArray<KaraokeSetlist>, any Error>, for filter: Filter, startIndex: Int) {
        isLoading = false
        isLoadingMore = false
        pageTask = nil
        switch result {
        case let .success(page):
            var seen = startIndex == 0 ? Set<String>() : Set(setlists.map(\.id))
            let fresh = page.elements.filter { seen.insert($0.id).inserted }
            setlists = startIndex == 0 ? fresh : setlists + fresh
            shownFilter = filter
            nextOffset = startIndex + page.sourceCount
            canLoadMore = page.sourceCount >= pageSize
        case let .failure(error):
            DebugLogger.log("Setlists page at \(startIndex) failed: \(error.localizedDescription)", category: .network)
            if startIndex == 0 {
                // Results for another year or search would look like results for this one.
                if shownFilter != filter { setlists = [] }
                loadFailed = setlists.isEmpty
            } else {
                // Reaching the end of the list again retries.
                canLoadMore = true
            }
        }
    }
}
