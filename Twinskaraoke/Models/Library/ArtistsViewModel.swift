import Combine
import Foundation

@MainActor
final class ArtistsViewModel: ObservableObject {
    @Published var artists: [Artist] = []
    @Published var isLoading = false
    @Published var loadFailed = false
    @Published var canLoadMore = true
    private var page = 0
    private let pageSize = 25
    private var loadOwnership = LatestLoadOwnershipGate()
    private var activeTask: Task<Void, Never>?

    func fetchInitial() {
        guard artists.isEmpty, !isLoading else { return }
        page = 0
        canLoadMore = true
        loadFailed = false
        load(reset: true)
    }

    func refresh() async {
        cancelActiveLoad()
        page = 0
        canLoadMore = true
        loadFailed = false
        let task = load(reset: true)
        await task?.value
    }

    func loadMoreIfNeeded(current: Artist) {
        guard let idx = artists.firstIndex(of: current) else { return }
        if idx >= artists.count - 5, !isLoading, canLoadMore {
            load(reset: false)
        }
    }

    @discardableResult
    private func load(reset: Bool) -> Task<Void, Never>? {
        guard !isLoading else { return nil }
        let startIndex = page * pageSize
        let urlString =
            "\(StorageHost.api)/api/artists?startIndex=\(startIndex)&pageSize=\(pageSize)&search=&sortBy=Name&sortDescending=False"
        guard let url = URL(string: urlString) else { return nil }
        isLoading = true
        let loadToken = loadOwnership.begin()
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        let task = Task { @MainActor [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.applyArtistsResponse(
                    data,
                    statusCode: statusCode,
                    reset: reset,
                    loadToken: loadToken
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyArtistsResponse(
                    nil,
                    statusCode: nil,
                    reset: reset,
                    loadToken: loadToken
                )
            }
        }
        activeTask = task
        return task
    }

    private func applyArtistsResponse(
        _ data: Data?,
        statusCode: Int?,
        reset: Bool,
        loadToken: LatestLoadOwnershipGate.Token
    ) {
        guard loadOwnership.finish(loadToken) else { return }
        activeTask = nil
        defer { isLoading = false }

        guard let statusCode, (200 ... 299).contains(statusCode),
              let data,
              let decoded = try? JSONDecoder().decode([Artist].self, from: data)
        else {
            loadFailed = reset && artists.isEmpty
            return
        }

        loadFailed = false
        if reset {
            artists = decoded
        } else {
            let existing = Set(artists.map(\.id))
            artists += decoded.filter { !existing.contains($0.id) }
        }
        page += 1
        canLoadMore = decoded.count == pageSize
    }

    private func cancelActiveLoad() {
        loadOwnership.cancel()
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
    }

    deinit {
        activeTask?.cancel()
    }
}

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published var artist: Artist?
    @Published var isLoading = false
    @Published private(set) var hasLoadedDetail = false
    @Published var errorMessage: String?
    private var loadedID: String?
    private var loadOwnership = LatestLoadOwnershipGate()
    private var loadTask: URLSessionDataTask?

    func load(id: String, fallback: Artist?, force: Bool = false) {
        if !force, loadedID == id, hasLoadedDetail || isLoading { return }
        cancelActiveLoad()
        if artist == nil || loadedID != id { artist = fallback }
        loadedID = id
        hasLoadedDetail = false
        errorMessage = nil
        guard let url = URL(string: "\(StorageHost.api)/api/artist/\(id)") else { return }
        isLoading = true
        let loadToken = loadOwnership.begin()
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            Task { @MainActor [weak self, data, id, loadToken] in
                self?.applyArtistDetailResponse(data, id: id, loadToken: loadToken)
            }
        }
        loadTask = task
        task.resume()
    }

    private func applyArtistDetailResponse(
        _ data: Data?,
        id: String,
        loadToken: LatestLoadOwnershipGate.Token
    ) {
        guard loadedID == id, loadOwnership.finish(loadToken) else { return }
        loadTask = nil
        defer { isLoading = false }

        guard let data else {
            errorMessage = "Check your connection and try again."
            return
        }

        guard let decoded = try? JSONDecoder().decode(Artist.self, from: data) else {
            errorMessage = "The artist could not be loaded right now."
            return
        }

        artist = decoded
        hasLoadedDetail = true
        errorMessage = nil
    }

    private func cancelActiveLoad() {
        loadOwnership.cancel()
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    deinit {
        loadTask?.cancel()
    }
}
