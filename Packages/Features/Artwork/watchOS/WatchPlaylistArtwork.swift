import Foundation
import Observation

/// Uses the same detail endpoint and song-cover fallback as iPhone. Absolute
/// cover URLs are used as supplied; no new server-side transformations.
nonisolated enum WatchPlaylistArtwork {
    static func urls(for playlist: Playlist) -> [URL] {
        if let url = coverURL(path: playlist.media?.absolutePath, cloudflareID: playlist.media?.cloudflareId) {
            return [url]
        }
        let mosaic = playlist.mosaicMedia?.compactMap { coverURL(path: $0.absolutePath, cloudflareID: $0.cloudflareId) } ?? []
        if !mosaic.isEmpty { return Array(mosaic.prefix(4)) }
        return songURLs(playlist.songListDTOs ?? [])
    }

    static func songURLs(_ songs: [Song]) -> [URL] {
        Array(songs.compactMap { song in
            coverURL(path: song.coverArt?.absolutePath, cloudflareID: song.coverArt?.cloudflareId)
                ?? song.thumbnailURL
        }.prefix(4))
    }

    private static func coverURL(path: String?, cloudflareID: String?) -> URL? {
        if let path, let url = URL(string: path.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return url
        }
        return ArtworkURLBuilder.imageURL(cloudflareID: cloudflareID, path: path, variant: .thumbnail)
    }
}

@MainActor
@Observable
final class WatchPlaylistCoverLoader {
    private(set) var urls: [URL] = []
    private let loadDetail: @Sendable (String) async throws -> Playlist

    init(loadDetail: @escaping @Sendable (String) async throws -> Playlist = {
        let data = try await KaraokeAPIClient.playlistDetailData(id: $0)
        return try JSONDecoder().decode(Playlist.self, from: data)
    }) {
        self.loadDetail = loadDetail
    }

    func load(_ playlist: Playlist) async {
        urls = WatchPlaylistArtwork.urls(for: playlist)
        guard playlist.isPersonal, urls.isEmpty else { return }
        let token = CredentialStore.token
        guard let detail = try? await loadDetail(playlist.id), !Task.isCancelled,
              token == CredentialStore.token else { return }
        urls = WatchPlaylistArtwork.urls(for: detail)
    }
}
