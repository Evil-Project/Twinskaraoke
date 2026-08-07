import Foundation
import Observation

@MainActor
@Observable
final class VideoGalleryViewModel {
    var videos: [GalleryVideo] = []
    var isLoading = false
    var errorMessage: String?
    var canLoadMore = true
    private var page = 1
    private let pageSize = 25
    private var loadGeneration = 0
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    func fetchInitial() {
        guard videos.isEmpty, !isLoading else { return }
        page = 1
        canLoadMore = true
        load(reset: true)
    }

    func refresh() {
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        page = 1
        canLoadMore = true
        load(reset: true)
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the videos have actually finished loading. Deliberately not an
    /// `async` overload of `refresh()` — in an async context Swift would
    /// prefer the async overload and recurse.
    func refreshVideos() async {
        refresh()
        await activeTask?.value
    }

    /// Pulls the next page regardless of scroll position.
    ///
    /// Needed by the Watchalongs filter: watchalongs are a handful of items in
    /// a ~1400-video catalogue, so the filtered list can be empty (and therefore
    /// have nothing to trigger `loadMoreIfNeeded`) while pages remain unread.
    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        load(reset: false)
    }

    func loadMoreIfNeeded(current: GalleryVideo) {
        guard let idx = videos.firstIndex(of: current) else { return }
        if idx >= videos.count - 5, !isLoading, canLoadMore {
            load(reset: false)
        }
    }

    private func load(reset: Bool) {
        guard !isLoading else { return }
        guard let request = try? KaraokeAPIClient.request(
            path: "/api/videos",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "sortBy", value: "UploadedAt"),
                URLQueryItem(name: "sortDescending", value: "True"),
            ]
        ) else {
            errorMessage = "The video gallery endpoint is unavailable."
            return
        }
        isLoading = true
        if reset { errorMessage = nil }
        loadGeneration += 1
        let generation = loadGeneration
        activeTask = Task { [weak self] in
            do {
                let data = try await KaraokeAPIClient.data(for: request)
                self?.applyVideosResponse(data, failureMessage: nil, reset: reset, generation: generation)
            } catch let error as URLError {
                self?.applyVideosResponse(
                    nil,
                    failureMessage: error.localizedDescription,
                    reset: reset,
                    generation: generation
                )
            } catch KaraokeAPIClient.APIError.httpStatus(let statusCode) {
                self?.applyVideosResponse(
                    nil,
                    failureMessage: "The server returned HTTP \(statusCode).",
                    reset: reset,
                    generation: generation
                )
            } catch {
                self?.applyVideosResponse(
                    nil,
                    failureMessage: "The video response could not be read.",
                    reset: reset,
                    generation: generation
                )
            }
        }
    }

    private func applyVideosResponse(
        _ data: Data?,
        failureMessage: String?,
        reset: Bool,
        generation: Int
    ) {
        guard generation == loadGeneration else { return }
        defer {
            isLoading = false
            activeTask = nil
        }

        if let failureMessage {
            errorMessage = failureMessage
            return
        }
        guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
            errorMessage = "The video response could not be read."
            return
        }

        let previousCount = reset ? 0 : videos.count
        if reset {
            videos = Self.uniqueVideos(decoded.items)
        } else {
            var seen = Set(videos.map(\.id))
            videos += decoded.items.filter { seen.insert($0.id).inserted }
        }
        page += 1
        let addedCount = videos.count - previousCount
        canLoadMore = addedCount > 0 && videos.count < decoded.totalCount
        errorMessage = nil
    }

    private static func uniqueVideos(_ videos: [GalleryVideo]) -> [GalleryVideo] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    deinit {
        activeTask?.cancel()
    }
}

/// Videos related to the one being watched.
///
/// `/api/videos` ignores `songId`, `createdBy` and `isWatchalong` as filters —
/// passing them returns the unfiltered catalogue — so relatedness is expressed
/// through the two parameters the endpoint actually honours: `search`, which
/// matches title, description and uploader, and `category`.
@MainActor
@Observable
final class SimilarVideosViewModel {
    var videos: [GalleryVideo] = []
    var isLoading = false
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var loadedForID: String?

    private static let resultLimit = 20

    func fetch(like video: GalleryVideo) {
        guard loadedForID != video.id else { return }
        loadedForID = video.id
        activeTask?.cancel()
        isLoading = true

        activeTask = Task { [weak self] in
            var collected: [GalleryVideo] = []
            var seen: Set<String> = [video.id]

            for query in Self.queries(for: video) {
                guard !Task.isCancelled else { return }
                let batch = await Self.load(query)
                collected += batch.filter { seen.insert($0.id).inserted }
                if collected.count >= Self.resultLimit { break }
            }

            guard !Task.isCancelled else { return }
            self?.apply(Array(collected.prefix(Self.resultLimit)))
        }
    }

    /// Progressively weaker notions of "similar", most specific first.
    private static func queries(for video: GalleryVideo) -> [[URLQueryItem]] {
        var queries: [[URLQueryItem]] = []

        if video.isWatchalongVideo {
            queries.append([URLQueryItem(name: "category", value: "2")])
        }
        // Other performances of the same song.
        if let songTitle = video.songTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !songTitle.isEmpty
        {
            queries.append([URLQueryItem(name: "search", value: songTitle)])
        }
        // More from the same uploader.
        if let creator = video.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creator.isEmpty
        {
            queries.append([URLQueryItem(name: "search", value: creator)])
        }
        // Last resort so the shelf is never empty.
        queries.append([])
        return queries
    }

    private static func load(_ queryItems: [URLQueryItem]) async -> [GalleryVideo] {
        let items = queryItems + [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: String(resultLimit)),
            URLQueryItem(name: "sortBy", value: "UploadedAt"),
            URLQueryItem(name: "sortDescending", value: "True"),
        ]
        guard let request = try? KaraokeAPIClient.request(path: "/api/videos", queryItems: items),
              let data = try? await KaraokeAPIClient.data(for: request),
              let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data)
        else { return [] }
        return decoded.items
    }

    private func apply(_ videos: [GalleryVideo]) {
        self.videos = videos
        isLoading = false
        activeTask = nil
    }

    deinit {
        activeTask?.cancel()
    }
}
