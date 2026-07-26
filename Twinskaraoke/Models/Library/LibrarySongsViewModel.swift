import Combine
import Foundation

@MainActor
final class LibrarySongsViewModel: ObservableObject {
    @Published var songs: [Song] = [] {
        didSet { songsGeneration &+= 1 }
    }
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var sort: LibrarySongSort = .recentlyAdded {
        didSet { rebuildDisplayedSongs() }
    }
    @Published var searchText = ""
    @Published private(set) var displayedSongs: [Song] = []
    @Published private(set) var loadFailed = false
    private var hasLoaded = false
    private var canLoadMore = true
    private var page = 1
    private var requestToken = 0
    private var isReplacing = false
    private var activeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var songsGeneration: UInt64 = 0
    private var sortCache: (sort: LibrarySongSort, generation: UInt64, songs: [Song])?
    private let pageSize = 40

    init() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuildDisplayedSongs() }
            .store(in: &cancellables)
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
        let sorted: [Song] = switch sort {
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
        sortCache = (sort, songsGeneration, sorted)
        return sorted
    }

    private func rebuildDisplayedSongs() {
        let sorted = sortedSongs

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedSongs = sorted
            return
        }
        displayedSongs = sorted.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.displayArtist.localizedCaseInsensitiveContains(query)
                || song.displayTitle.localizedCaseInsensitiveContains(query)
        }
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
        if let token = CredentialStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        GuestIdentity.applyIfNeeded(to: &request)
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
        let filtered = decoded.filter {
            !$0.title.localizedCaseInsensitiveContains("Temporary Stream Audio")
        }
        let pageSongs = filtered.isEmpty ? decoded : filtered

        if replace {
            songs = pageSongs
            hasLoaded = true
        } else {
            let existing = Set(songs.map(\.id))
            songs += pageSongs.filter { !existing.contains($0.id) }
        }
        rebuildDisplayedSongs()

        canLoadMore = pageSongs.count == pageSize
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
    }
}
