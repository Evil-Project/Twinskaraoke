import Combine
import Foundation

@MainActor
final class VideoGalleryViewModel: ObservableObject {
    @Published var videos: [GalleryVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canLoadMore = true
    private var page = 1
    private let pageSize = 25
    private var loadGeneration = 0
    private var activeTask: Task<Void, Never>?

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

@MainActor
final class SimilarVideosViewModel: ObservableObject {
    @Published var videos: [GalleryVideo] = []
    @Published var isLoading = false

    func fetch(excluding currentID: String) {
        guard videos.isEmpty, !isLoading else { return }
        guard let request = try? KaraokeAPIClient.request(
            path: "/api/videos",
            queryItems: [
                URLQueryItem(name: "startIndex", value: "0"),
                URLQueryItem(name: "pageSize", value: "20"),
                URLQueryItem(name: "sortBy", value: "CreatedAt"),
                URLQueryItem(name: "sortDescending", value: "true"),
            ]
        ) else { return }
        isLoading = true
        Task { [weak self] in
            let data = try? await KaraokeAPIClient.data(for: request)
            self?.applySimilarVideosResponse(data, excluding: currentID)
        }
    }

    private func applySimilarVideosResponse(_ data: Data?, excluding currentID: String) {
        defer { isLoading = false }

        guard let data, let decoded = try? JSONDecoder().decode(VideosResponse.self, from: data) else {
            return
        }

        videos = decoded.items.filter { $0.id != currentID }
    }
}
