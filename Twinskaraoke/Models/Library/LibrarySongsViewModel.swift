import Combine
import Foundation

@MainActor
final class LibrarySongsViewModel: ObservableObject {
    struct PageResponse: Sendable {
        let data: Data
        let statusCode: Int
    }

    typealias PageLoader = @Sendable (URLRequest) async throws -> PageResponse

    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var sort: LibrarySongSort = .recentlyAdded {
        didSet { rebuildDisplayedSongs() }
    }
    @Published var searchText = "" {
        didSet { rebuildDisplayedSongs() }
    }
    @Published private(set) var displayedSongs: [Song] = []
    private var hasLoaded = false
    private var canLoadMore = true
    private var page = 1
    private var loadOwnership = LatestLoadOwnershipGate()
    private var activeTask: Task<Void, Never>?
    private let pageLoader: PageLoader
    private let pageSize = 40

    init(
        pageLoader: @escaping PageLoader = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return PageResponse(
                data: data,
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
    ) {
        self.pageLoader = pageLoader
    }

    private func rebuildDisplayedSongs() {
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

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedSongs = sorted
            return
        }
        displayedSongs = sorted.filter { song in
            song.title.localizedStandardContains(query)
                || song.displayArtist.localizedStandardContains(query)
                || song.displayTitle.localizedStandardContains(query)
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        fetch(page: 1, replace: true)
    }

    func refresh() async {
        cancelActiveLoad()
        hasLoaded = false
        canLoadMore = true
        page = 1
        let task = fetch(page: 1, replace: true)
        await task?.value
    }

    func loadMoreIfNeeded(current: Song) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let visible = displayedSongs
        guard let index = visible.firstIndex(where: { $0.id == current.id }) else { return }
        guard index >= visible.count - 8 else { return }
        fetch(page: page + 1, replace: false)
    }

    func loadMore() {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fetch(page: page + 1, replace: false)
    }

    @discardableResult
    private func fetch(page: Int, replace: Bool) -> Task<Void, Never>? {
        guard canLoadMore || replace else { return nil }
        guard !isLoading, !isLoadingMore else { return nil }
        guard let url = URL(string: "\(StorageHost.api)/api/songs") else { return nil }

        let loadToken = loadOwnership.begin()
        if replace {
            isLoading = songs.isEmpty
        } else {
            isLoadingMore = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "nk.token") {
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

        let pageLoader = pageLoader
        let task = Task { @MainActor [weak self, pageLoader] in
            do {
                let response = try await pageLoader(request)
                guard !Task.isCancelled else { return }
                self?.applyResponse(
                    response,
                    error: nil,
                    page: page,
                    replace: replace,
                    loadToken: loadToken
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyResponse(
                    nil,
                    error: error,
                    page: page,
                    replace: replace,
                    loadToken: loadToken
                )
            }
        }
        activeTask = task
        return task
    }

    private func applyResponse(
        _ response: PageResponse?,
        error: Error?,
        page: Int,
        replace: Bool,
        loadToken: LatestLoadOwnershipGate.Token
    ) {
        guard loadOwnership.finish(loadToken) else { return }
        activeTask = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        if let error {
            DebugLogger.log("Library songs fetch failed: \(error.localizedDescription)", category: .network)
            return
        }
        guard let response else {
            DebugLogger.log("Library songs returned no response", category: .network)
            return
        }
        guard (200 ... 299).contains(response.statusCode) else {
            DebugLogger.log("Library songs HTTP \(response.statusCode)", category: .network)
            return
        }

        let decoded = Self.decodeSongs(from: response.data)
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

    private func cancelActiveLoad() {
        loadOwnership.cancel()
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        isLoadingMore = false
    }

    deinit {
        activeTask?.cancel()
    }

    private static func decodeSongs(from data: Data?) -> [Song] {
        guard let data else { return [] }
        if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return decoded.items
        }
        return SongPayloadDecoder.decodeSongs(from: data) ?? []
    }
}
