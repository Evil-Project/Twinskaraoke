import Foundation
import SDWebImage
import SDWebImageSwiftUI

@MainActor
final class ArtworkPrefetcher {
    static let shared = ArtworkPrefetcher()

    private let prefetcher = SDWebImagePrefetcher.shared
    private var recentlyRequested: [String: Date] = [:]
    private let reuseWindow: TimeInterval = 45

    private init() {
        prefetcher.maxConcurrentPrefetchCount = 2
    }

    func prefetchSongs(_ songs: [Song], limit: Int = 18, reason: String) {
        prefetch(urls: songs.compactMap(\.imageURL), limit: limit, reason: reason)
    }

    func prefetchPlaylists(_ playlists: [Playlist], limit: Int = 12, reason: String) {
        let urls = playlists.flatMap { playlist -> [URL] in
            var values: [URL] = []
            if let imageURL = playlist.imageURL {
                values.append(imageURL)
            }
            values.append(contentsOf: playlist.initialMosaicArtworkURLs)
            return values
        }
        prefetch(urls: urls, limit: limit, reason: reason)
    }

    func prefetch(urls: [URL], limit: Int = 18, reason: String) {
        let selected = freshUniqueURLs(from: urls, limit: limit)
        guard !selected.isEmpty else { return }

        let context: [SDWebImageContextOption: Any] = [
            .imageThumbnailPixelSize: NSValue(cgSize: ImageCacheConfig.thumbnailPixelSize),
            .storeCacheType: NSNumber(value: SDImageCacheType.memory.rawValue),
            .originalStoreCacheType: NSNumber(value: SDImageCacheType.disk.rawValue),
            .originalQueryCacheType: NSNumber(value: SDImageCacheType.disk.rawValue),
        ]

        DebugLogger.log(
            "Prefetching \(selected.count) artwork images for \(reason)",
            category: .cache
        )

        prefetcher.prefetchURLs(
            selected,
            options: [.lowPriority, .retryFailed, .scaleDownLargeImages],
            context: context,
            progress: nil
        ) { finished, skipped in
            DebugLogger.log(
                "Artwork prefetch complete for \(reason): finished=\(finished), skipped=\(skipped)",
                category: .cache
            )
        }
    }

    private func freshUniqueURLs(from urls: [URL], limit: Int) -> [URL] {
        let now = Date()
        recentlyRequested = recentlyRequested.filter { now.timeIntervalSince($0.value) < reuseWindow }

        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            guard recentlyRequested[key] == nil else { continue }
            recentlyRequested[key] = now
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }
}
