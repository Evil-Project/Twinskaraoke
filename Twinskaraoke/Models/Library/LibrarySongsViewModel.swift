import Foundation
import Observation

@MainActor
@Observable
final class LibrarySongsViewModel {
    var songs: [Song] = [] {
        didSet { songsGeneration &+= 1 }
    }
    var isLoading = false
    var isLoadingMore = false
    var sort: LibrarySongSort = .recentlyAdded {
        didSet { rebuildDisplayedSongs() }
    }
    var searchText = "" {
        didSet { scheduleDisplayedSongsRebuild() }
    }
    private(set) var displayedSongs: [Song] = []
    private(set) var loadFailed = false
    private var hasLoaded = false
    private var canLoadMore = true
    private var page = 1
    private var requestToken = 0
    private var isReplacing = false
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastRebuiltSearchText = ""
    private var songsGeneration: UInt64 = 0
    private var sortCache: (sort: LibrarySongSort, generation: UInt64, songs: [Song])?
    private let pageSize = 40

    /// Server matches for `remoteQuery`. `songs` holds only the pages scrolled
    /// into view — a few dozen of a catalog of thousands — so filtering it
    /// alone could not find most songs, and said so as No Results.
    private(set) var isSearchingRemotely = false
    private var remoteResults: [Song] = []
    private var remoteQuery = ""
    @ObservationIgnored private var remoteSearchTask: Task<Void, Never>?
    @ObservationIgnored private let searchSongs: @MainActor (String) async throws -> [Song]

    init(searchSongs: @escaping @MainActor (String) async throws -> [Song] = {
        try await KaraokeAPIClient.searchSongs(query: $0, pageSize: 100)
    }) {
        self.searchSongs = searchSongs
    }

    /// Replaces `$searchText.debounce(200ms).removeDuplicates()`. Filtering a
    /// large library runs localized comparisons per song, so keystrokes must
    /// still coalesce.
    private func scheduleDisplayedSongsRebuild() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            guard searchText != lastRebuiltSearchText else { return }
            lastRebuiltSearchText = searchText
            rebuildDisplayedSongs()
            startRemoteSearch()
        }
    }

    private func startRemoteSearch() {
        remoteSearchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            remoteSearchTask = nil
            remoteQuery = ""
            remoteResults = []
            isSearchingRemotely = false
            return
        }
        isSearchingRemotely = true
        remoteSearchTask = Task { [weak self] in
            guard let self else { return }
            let found: [Song]
            do {
                found = try await searchSongs(query)
            } catch {
                guard !Task.isCancelled else { return }
                found = []
            }
            guard !Task.isCancelled else { return }
            remoteResults = found.filter { !Self.isPlaceholder($0) }
            remoteQuery = query
            isSearchingRemotely = false
            remoteSearchTask = nil
            rebuildDisplayedSongs()
        }
    }

    // Sorting is the expensive half of a rebuild; cache it per (sort, songs)
    // so search keystrokes only pay for the filter pass.
    private var sortedSongs: [Song] {
        if let sortCache,
           sortCache.sort == sort,
           sortCache.generation == songsGeneration
        {
            return sortCache.songs
        }
        let sorted = Self.sorted(songs, by: sort)
        sortCache = (sort, songsGeneration, sorted)
        return sorted
    }

    private static func sorted(_ songs: [Song], by sort: LibrarySongSort) -> [Song] {
        switch sort {
        case .recentlyAdded:
            songs
        case .title:
            songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            songs.sorted {
                $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending
            }
        case .duration:
            songs.sorted { $0.duration < $1.duration }
        }
    }

    private static func isPlaceholder(_ song: Song) -> Bool {
        song.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
    }

    private func rebuildDisplayedSongs() {
        let sorted = sortedSongs

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedSongs = sorted
            return
        }
        let local = sorted.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.displayArtist.localizedCaseInsensitiveContains(query)
                || song.displayTitle.localizedCaseInsensitiveContains(query)
        }
        guard remoteQuery == query, !remoteResults.isEmpty else {
            displayedSongs = local
            return
        }
        var seen = Set(local.map(\.id))
        let extra = remoteResults.filter { seen.insert($0.id).inserted }
        // Recently Added has no order to merge into beyond what the pages
        // give; the other sorts apply across both.
        displayedSongs = sort == .recentlyAdded ? local + extra : Self.sorted(local + extra, by: sort)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        fetch(page: 1, replace: true)
    }

    func refresh() {
        activeTask?.cancel()
        activeTask = nil
        requestToken += 1
        isLoading = false
        isLoadingMore = false
        hasLoaded = false
        canLoadMore = true
        fetch(page: 1, replace: true)
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the songs have actually finished loading. Deliberately not an
    /// `async` overload of `refresh()` — in an async context Swift would
    /// prefer the async overload and recurse.
    func refreshSongs() async {
        refresh()
        await activeTask?.value
    }

    func loadMoreIfNeeded(current: Song) {
        guard canLoadMore, !isLoading, !isLoadingMore, !isReplacing else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let visible = displayedSongs
        guard let index = visible.firstIndex(where: { $0.id == current.id }) else { return }
        guard index >= visible.count - 8 else { return }
        fetch(page: page + 1, replace: false)
    }

    func loadMore() {
        guard canLoadMore, !isLoading, !isLoadingMore, !isReplacing else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fetch(page: page + 1, replace: false)
    }

    private func fetch(page: Int, replace: Bool) {
        guard canLoadMore || replace else { return }
        guard !isLoading, !isLoadingMore else { return }
        guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return }

        requestToken += 1
        let token = requestToken
        if replace {
            loadFailed = false
            isReplacing = true
            isLoading = songs.isEmpty
        } else {
            isLoadingMore = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "page": page,
            "pageSize": pageSize,
            "search": "",
            "sortBy": "CreatedAt",
            "sortDescending": true,
        ])

        // Routed through KaraokeAPIClient.data so 401s trigger the
        // session-expired flow and transient failures get retried.
        activeTask = Task { [weak self] in
            do {
                if let token = try CredentialStore.requestToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                GuestIdentity.applyIfNeeded(to: &request)
                let data = try await KaraokeAPIClient.data(
                    for: request,
                    retriesNonIdempotentRequest: true
                )
                self?.applyResponse(data, error: nil, page: page, replace: replace, token: token)
            } catch {
                self?.applyResponse(nil, error: error, page: page, replace: replace, token: token)
            }
        }
    }

    private func applyResponse(
        _ data: Data?,
        error: Error?,
        page: Int,
        replace: Bool,
        token: Int
    ) {
        guard token == requestToken else { return }
        defer {
            activeTask = nil
            isLoading = false
            isLoadingMore = false
            if replace { isReplacing = false }
        }

        if let error {
            guard (error as? URLError)?.code != .cancelled, !(error is CancellationError) else { return }
            DebugLogger.log("Library songs fetch failed: \(error.localizedDescription)", category: .network)
            if replace, songs.isEmpty {
                hasLoaded = true
                loadFailed = true
            }
            return
        }

        guard let decoded = Self.decodeSongs(from: data) else {
            DebugLogger.log("Library songs decode failed", category: .network)
            if replace, songs.isEmpty {
                hasLoaded = true
                loadFailed = true
            }
            return
        }
        let filtered = decoded.filter { !Self.isPlaceholder($0) }
        let pageSongs = filtered.isEmpty ? decoded : filtered

        if replace {
            songs = pageSongs
            hasLoaded = true
        } else {
            let existing = Set(songs.map(\.id))
            songs += pageSongs.filter { !existing.contains($0.id) }
        }
        rebuildDisplayedSongs()

        // The server paginates on the unfiltered count; using the filtered
        // pageSongs here would stop infinite scroll on a page with filtered items.
        canLoadMore = decoded.count == pageSize
        if !pageSongs.isEmpty || replace {
            self.page = page
        }
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(pageSongs.prefix(18)),
            limit: 18,
            reason: replace ? "library songs initial" : "library songs page",
            variant: .row
        )
    }

    private static func decodeSongs(from data: Data?) -> [Song]? {
        guard let data else { return nil }
        if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return decoded.items
        }
        return SongPayloadDecoder.decodeSongs(from: data)
    }

    deinit {
        activeTask?.cancel()
        remoteSearchTask?.cancel()
    }
}
