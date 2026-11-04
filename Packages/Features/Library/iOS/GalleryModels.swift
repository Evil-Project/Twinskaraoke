import Foundation
import Observation

nonisolated struct GalleryArtist: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let socialLink: String?
    let userId: String?
    let arts: [GalleryArt]?
}

nonisolated struct GalleryArt: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let fileName: String?
    let description: String?
    let credit: String?
    let cloudflareId: String?
    let absolutePath: String?
    let upvotes: Int?
    var imageURL: URL? {
        imageURL(variant: .card)
    }

    var fullHDImageURL: URL? {
        imageURL(variant: .fullHD) ?? imageURL
    }

    var heroImageURL: URL? {
        imageURL(variant: .hero)
    }

    var blurPreviewURL: URL? {
        imageURL(variant: .blur)
    }

    func imageURL(variant: ArtworkImageVariant) -> URL? {
        ArtworkURLBuilder.imageURL(
            cloudflareID: cloudflareId,
            path: absolutePath,
            variant: variant
        )
    }
}

@MainActor
@Observable
final class ArtGalleryViewModel {
    var artists: [GalleryArtist] = []
    var isLoading = false
    var loadFailed = false
    @ObservationIgnored private let store: GalleryCatalogStore
    @ObservationIgnored private let download: @Sendable () async throws -> Data
    @ObservationIgnored private let refreshTracker = RefreshTracker()

    init(
        store: GalleryCatalogStore = .shared,
        download: @escaping @Sendable () async throws -> Data = { try await ArtGalleryViewModel.downloadCatalog() }
    ) {
        self.store = store
        self.download = download
    }

    /// Shows the saved catalogue, and downloads a new one when there is none,
    /// when it's older than `GalleryCatalogStore.maxAge`, or when `force` is set.
    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        refreshTracker.track(Task { [weak self] in
            await self?.performLoad(force: force)
        })
    }

    /// `fetch`, then waits until the load has finished.
    ///
    /// No `cancellingPrevious` in `fetch`: it bails while a load is already
    /// running, so a second call never starts a competing task — it just
    /// waits on the one in flight.
    func load(force: Bool = false) async {
        fetch(force: force)
        await refreshTracker.wait()
    }

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the gallery has actually finished loading.
    func refreshGallery() async {
        await load(force: true)
    }

    private func performLoad(force: Bool) async {
        defer { isLoading = false }
        if let cached = await store.cached() {
            if artists.isEmpty {
                artists = cached.artists
            }
            if !force, store.isCurrent(cached) {
                loadFailed = false
                return
            }
        }
        do {
            let data = try await download()
            artists = try await store.update(from: data)
            loadFailed = false
        } catch {
            // A failed refresh keeps whatever is already on screen.
            loadFailed = artists.isEmpty
        }
    }

    nonisolated static func downloadCatalog() async throws -> Data {
        let request = try KaraokeAPIClient.request(
            path: "/api/media/artists",
            queryItems: [URLQueryItem(name: "loadArts", value: "true")]
        )
        return try await KaraokeAPIClient.data(for: request)
    }
}
