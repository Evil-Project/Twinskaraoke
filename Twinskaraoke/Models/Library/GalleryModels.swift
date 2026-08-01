import Combine
import Foundation

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
final class ArtGalleryViewModel: ObservableObject {
    @Published var artists: [GalleryArtist] = []
    @Published var isLoading = false
    @Published var loadFailed = false
    private var hasLoaded = false
    private var loadOwnership = LatestLoadOwnershipGate()
    private var activeTask: URLSessionDataTask?

    func fetch(force: Bool = false) {
        if isLoading {
            guard force else { return }
            cancelActiveLoad()
        }
        guard force || !hasLoaded else { return }
        guard let url = URL(string: "\(StorageHost.api)/api/media/artists?loadArts=true")
        else { return }
        loadFailed = false
        isLoading = true
        let loadToken = loadOwnership.begin()
        var request = URLRequest(url: url)
        GuestIdentity.applyIfNeeded(to: &request)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let filtered = data.flatMap { data -> [GalleryArtist]? in
                guard let decoded = try? JSONDecoder().decode([GalleryArtist].self, from: data) else {
                    return nil
                }
                return decoded
                    .filter { ($0.arts?.count ?? 0) > 0 }
                    .sorted { ($0.arts?.count ?? 0) > ($1.arts?.count ?? 0) }
            }
            Task { @MainActor [weak self, filtered, loadToken] in
                self?.applyResponse(filtered, loadToken: loadToken)
            }
        }
        activeTask = task
        task.resume()
    }

    private func applyResponse(
        _ filtered: [GalleryArtist]?,
        loadToken: LatestLoadOwnershipGate.Token
    ) {
        guard loadOwnership.finish(loadToken) else { return }
        activeTask = nil
        if let filtered {
            artists = filtered
            hasLoaded = true
            loadFailed = false
        } else {
            loadFailed = artists.isEmpty
        }
        isLoading = false
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
