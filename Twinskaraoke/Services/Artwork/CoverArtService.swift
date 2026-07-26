import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Network fetches backing the full-screen player's cover-art actions, so the
/// view only holds intent handlers and the async work is task-cancellable.
nonisolated enum CoverArtService {
    struct ArtistCredit: Sendable {
        let name: String?
        let link: String?
    }

    struct RandomArt: Sendable {
        let imageURL: URL
        let artistCredit: String?
    }

    #if canImport(UIKit)
        /// Downloads and decodes off-main; a full-HD decode on the main queue
        /// can hitch the player UI.
        static func fetchImage(from url: URL) async -> UIImage? {
            guard let data = try? await URLSession.shared.data(from: url).0 else { return nil }
            return UIImage(data: data)
        }
    #endif

    static func fetchRandomYuriArt() async -> RandomArt? {
        let urlString = "\(StorageHost.api)/public/art/yuri/random"
        guard let apiURL = URL(string: urlString) else { return nil }
        var request = URLRequest(url: apiURL)
        GuestIdentity.applyIfNeeded(to: &request)
        guard let data = try? await URLSession.shared.data(for: request).0,
            let item = try? JSONDecoder().decode(RandomYuriArtItem.self, from: data),
            let baseURL = URL(string: item.url)
        else { return nil }
        let imageURL = ArtworkURLBuilder.variantURL(from: baseURL, variant: .hero) ?? baseURL
        return RandomArt(imageURL: imageURL, artistCredit: item.artistCredit)
    }

    /// Artist credit embedded in a song's `coverArt` payload, if present.
    static func fetchArtistCredit(songID: String) async -> ArtistCredit? {
        guard let request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "songs", songID]
        ) else { return nil }
        guard let data = try? await URLSession.shared.data(for: request).0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let coverArt = json["coverArt"] as? [String: Any],
            let artist = coverArt["artist"] as? [String: Any]
        else { return nil }
        return ArtistCredit(
            name: artist["name"] as? String,
            link: artist["socialLink"] as? String
        )
    }
}

private struct RandomYuriArtItem: Decodable {
    let url: String
    let artistCredit: String?
}
