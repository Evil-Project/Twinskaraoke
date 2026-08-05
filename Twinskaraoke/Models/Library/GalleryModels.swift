import Foundation
import Observation

struct GalleryArtist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let socialLink: String?
    let userId: String?
    let arts: [GalleryArt]?
}

struct GalleryArt: Codable, Identifiable, Equatable {
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
    private var hasLoaded = false
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    /// Awaitable reload for pull-to-refresh; keeps the refresh spinner alive
    /// until the gallery has actually finished loading.
    func refreshGallery() async {
        fetch(force: true)
        await activeTask?.value
    }

    func fetch(force: Bool = false) {
        guard !isLoading else { return }
        guard force || !hasLoaded else { return }
        guard let request = try? KaraokeAPIClient.request(
            path: "/api/media/artists",
            queryItems: [URLQueryItem(name: "loadArts", value: "true")]
        ) else { return }
        loadFailed = false
        isLoading = true
        activeTask = Task { [weak self] in
            let data = try? await KaraokeAPIClient.data(for: request)
            let filtered = data.flatMap { data -> [GalleryArtist]? in
                guard let decoded = try? JSONDecoder().decode([GalleryArtist].self, from: data) else {
                    return nil
                }
                return decoded
                    .filter { ($0.arts?.count ?? 0) > 0 }
                    .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
            }
            guard let self else { return }
            if let filtered {
                artists = filtered
                hasLoaded = true
                loadFailed = false
            } else {
                loadFailed = artists.isEmpty
            }
            isLoading = false
            activeTask = nil
        }
    }
}
