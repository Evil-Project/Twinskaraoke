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
    static let songWindow = 36
    static let playlistWindow = 24

    private let prefetcher = SDWebImagePrefetcher.shared
    private var recentlyRequested: [String: Date] = [:]
    private var activePrefetches: [String: ActivePrefetch] = [:]
    private let reuseWindow: TimeInterval = 45
    private let warmPrefetcher: SDWebImagePrefetcher = {
        let prefetcher = SDWebImagePrefetcher()
        prefetcher.maxConcurrentPrefetchCount = 2
        return prefetcher
    }()

    private var warmTokens: [String: SDWebImagePrefetchToken] = [:]
    private var warmRequests: [String: Int] = [:]

    private init() {
        prefetcher.maxConcurrentPrefetchCount = 3
    }
    func warmCollection(
        songs: [Song],
        reason: String,
        variant: ArtworkImageVariant = .row
    ) {
        let request = beginWarmRequest(reason: reason)
        Task.detached(priority: .utility) {
            let unique = Self.uniqueWarmURLs(for: songs, variant: variant)
            await MainActor.run {
                self.startWarm(urls: unique, reason: reason, request: request)
            }
        }
    }
    func warmCollection(
        playlists: [Playlist],
        reason: String,
        variant: ArtworkImageVariant = .thumbnail
    ) {
        let request = beginWarmRequest(reason: reason)
        var seen = Set<String>()
        let unique = Self.urls(for: playlists, variant: variant)
            .map { ArtworkURLBuilder.variantURL(from: $0, variant: variant) ?? $0 }
            .filter { seen.insert($0.absoluteString).inserted }
        startWarm(urls: unique, reason: reason, request: request)
    }
    private func beginWarmRequest(reason: String) -> Int {
        warmTokens.removeValue(forKey: reason)?.cancel()
        let next = (warmRequests[reason] ?? 0) + 1
        warmRequests[reason] = next
        return next
    }

    nonisolated private static func uniqueWarmURLs(
        for songs: [Song],
        variant: ArtworkImageVariant
    ) -> [URL] {
        var seen = Set<String>()
        return urls(for: songs, variant: variant)
            .map { ArtworkURLBuilder.variantURL(from: $0, variant: variant) ?? $0 }
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private func startWarm(urls: [URL], reason: String, request: Int) {
        guard warmRequests[reason] == request else { return }
        let unique = urls.filter { !ArtworkFailureBackoff.shared.isBlocked($0) }
        guard !unique.isEmpty else { return }

        DebugLogger.log(
            "Warming \(unique.count) artwork images for \(reason)",
            category: .cache
        )
        warmTokens[reason] = warmPrefetcher.prefetchURLs(
            unique,
            options: [.lowPriority],
            context: ImageCacheConfig.prefetchContext,
            progress: nil
        ) { [weak self] finished, skipped in
            Task { @MainActor [weak self] in
                DebugLogger.log(
                    "Artwork warm complete for \(reason): finished=\(finished), skipped=\(skipped)",
                    category: .cache
                )
                self?.warmTokens.removeValue(forKey: reason)
            }
        }
    }

    func cancelWarm(reason: String) {
        warmTokens.removeValue(forKey: reason)?.cancel()
        warmRequests[reason] = (warmRequests[reason] ?? 0) + 1
    }

    func prefetchSongs(
        _ songs: [Song],
        limit: Int = ArtworkPrefetcher.songWindow,
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
    nonisolated fileprivate static func urls(
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
        limit: Int = ArtworkPrefetcher.playlistWindow,
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
        limit: Int = ArtworkPrefetcher.songWindow,
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
            return min(limit, reason == "radio metadata" ? 8 : 6)
        }
        if AudioPlayerManager.shared.isPlaying {
            return min(limit, 12)
        }
        return min(limit, reason == "radio metadata" ? 10 : 24)
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
