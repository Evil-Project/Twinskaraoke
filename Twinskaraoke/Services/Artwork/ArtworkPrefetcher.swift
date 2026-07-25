import Foundation
import SDWebImage
import SDWebImageSwiftUI

@MainActor
struct ArtworkPrefetchSignature: Equatable {
    let songURLs: Set<String>
    let playlistURLs: Set<String>

    init(
        songs: [Song],
        playlists: [Playlist],
        variant: ArtworkImageVariant = .card
    ) {
        songURLs = Set(
            ArtworkPrefetcher.urls(for: songs, variant: variant).map(\.absoluteString)
        )
        playlistURLs = Set(
            ArtworkPrefetcher.urls(for: playlists, variant: variant).map(\.absoluteString)
        )
    }
}

@MainActor
struct ArtworkPrefetchTracker {
    private var lastSongURLs = Set<String>()
    private var lastPlaylistURLs = Set<String>()

    mutating func prefetch(
        signature: ArtworkPrefetchSignature,
        songs: [Song],
        playlists: [Playlist],
        songReason: String,
        playlistReason: String,
        songLimit: Int,
        playlistLimit: Int
    ) {
        if signature.songURLs != lastSongURLs {
            lastSongURLs = signature.songURLs
            if !signature.songURLs.isEmpty {
                ArtworkPrefetcher.shared.prefetchSongs(songs, limit: songLimit, reason: songReason)
            }
        }

        if signature.playlistURLs != lastPlaylistURLs {
            lastPlaylistURLs = signature.playlistURLs
            if !signature.playlistURLs.isEmpty {
                ArtworkPrefetcher.shared.prefetchPlaylists(
                    playlists,
                    limit: playlistLimit,
                    reason: playlistReason
                )
            }
        }
    }

    mutating func reset() {
        lastSongURLs.removeAll(keepingCapacity: true)
        lastPlaylistURLs.removeAll(keepingCapacity: true)
    }
}

@MainActor
final class ArtworkPrefetcher {
    private struct ActivePrefetch {
        let id: UUID
        let token: SDWebImagePrefetchToken
        let requestedKeys: Set<String>
        let selectedKeys: Set<String>
        let limit: Int
    }

    static let shared = ArtworkPrefetcher()

    private let prefetcher = SDWebImagePrefetcher.shared
    private var recentlyRequested: [String: Date] = [:]
    private var activePrefetches: [String: ActivePrefetch] = [:]
    private let reuseWindow: TimeInterval = 45

    private init() {
        prefetcher.maxConcurrentPrefetchCount = 3
    }

    func prefetchSongs(
        _ songs: [Song],
        limit: Int = 18,
        reason: String,
        variant: ArtworkImageVariant = .card
    ) {
        prefetch(
            urls: Self.urls(for: songs, variant: variant),
            limit: limit,
            reason: reason,
            variant: variant
        )
    }

    fileprivate static func urls(
        for songs: [Song],
        variant: ArtworkImageVariant
    ) -> [URL] {
        songs.compactMap { song -> URL? in
            switch variant {
            case .row:
                song.rowImageURL
            case .thumbnail:
                song.thumbnailURL
            case .hero:
                song.heroImageURL
            case .fullHD:
                song.fullHDImageURL
            default:
                song.imageURL
            }
        }
    }

    func prefetchPlaylists(
        _ playlists: [Playlist],
        limit: Int = 12,
        reason: String,
        variant: ArtworkImageVariant = .card
    ) {
        prefetch(
            urls: Self.urls(for: playlists, variant: variant),
            limit: limit,
            reason: reason,
            variant: variant
        )
    }

    fileprivate static func urls(
        for playlists: [Playlist],
        variant: ArtworkImageVariant
    ) -> [URL] {
        playlists.flatMap { playlist -> [URL] in
            var values: [URL] = []
            if let imageURL = playlist.imageURL(variant: variant) {
                values.append(imageURL)
            }
            values.append(contentsOf: playlist.initialMosaicArtworkURLs.compactMap {
                ArtworkURLBuilder.variantURL(from: $0, variant: variant)
            })
            return values
        }
    }

    func prefetch(
        urls: [URL],
        limit: Int = 18,
        reason: String,
        variant: ArtworkImageVariant = .card
    ) {
        let variantURLs = urls.map { url in
            ArtworkURLBuilder.variantURL(from: url, variant: variant) ?? url
        }
        let effectiveLimit = adjustedLimit(limit, reason: reason)
        let requestedKeys = Set(variantURLs.map(\.absoluteString))
        if let active = activePrefetches[reason],
           active.requestedKeys == requestedKeys,
           active.limit == effectiveLimit
        {
            return
        }

        cancel(reason: reason)
        let selected = freshUniqueURLs(from: variantURLs, limit: effectiveLimit)
        guard !selected.isEmpty else { return }

        DebugLogger.log(
            "Prefetching \(selected.count) artwork images for \(reason)",
            category: .cache
        )

        let requestID = UUID()
        let token = prefetcher.prefetchURLs(
            selected,
            options: [],
            context: ImageCacheConfig.prefetchContext,
            progress: nil
        ) { [weak self] finished, skipped in
            DebugLogger.log(
                "Artwork prefetch complete for \(reason): finished=\(finished), skipped=\(skipped)",
                category: .cache
            )
            Task { @MainActor [weak self] in
                guard self?.activePrefetches[reason]?.id == requestID else { return }
                self?.activePrefetches.removeValue(forKey: reason)
            }
        }
        if let token {
            activePrefetches[reason] = ActivePrefetch(
                id: requestID,
                token: token,
                requestedKeys: requestedKeys,
                selectedKeys: Set(selected.map(\.absoluteString)),
                limit: effectiveLimit
            )
        }
    }

    func cancel(reason: String) {
        guard let active = activePrefetches.removeValue(forKey: reason) else { return }
        active.token.cancel()
        for key in active.selectedKeys {
            recentlyRequested.removeValue(forKey: key)
        }
    }

    private func adjustedLimit(_ limit: Int, reason: String) -> Int {
        guard limit > 0 else { return 0 }
        if DownloadManager.shared.hasActiveQueue {
            return min(limit, reason == "radio metadata" ? 3 : 2)
        }
        if AudioPlayerManager.shared.isPlaying {
            return min(limit, 4)
        }
        return min(limit, reason == "radio metadata" ? 6 : 8)
    }

    private func freshUniqueURLs(from urls: [URL], limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        let now = Date()
        recentlyRequested = recentlyRequested.filter { now.timeIntervalSince($0.value) < reuseWindow }

        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            guard recentlyRequested[key] == nil else { continue }
            guard !ArtworkFailureBackoff.shared.isBlocked(url) else { continue }
            recentlyRequested[key] = now
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }
}
