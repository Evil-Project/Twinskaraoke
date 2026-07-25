import Combine
import Foundation
import SwiftUI

@MainActor
final class PlaylistCoverLoader: ObservableObject {
    @Published var artworkURLs: [URL] = []
    private var loadedID: String?
    private var fallbackSongs: [Song] = []
    private var loadedPlaylist: Playlist?
    private var loadTask: Task<Void, Never>?

    func load(playlistID: String, fallback: [Song]? = nil) {
        if loadedID == playlistID {
            fallbackSongs = fallback ?? fallbackSongs
            refreshFallbackArtwork()
            return
        }
        loadedID = playlistID
        fallbackSongs = fallback ?? []
        loadedPlaylist = nil
        artworkURLs = Self.extractArtworkURLs(fromSongs: fallbackSongs)
        loadTask?.cancel()

        guard let request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "playlist", playlistID]
        ) else {
            loadedID = nil
            return
        }

        loadTask = Task { [weak self, request] in
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                self?.handleLoadFailure(playlistID: playlistID)
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyLoadedPlaylistData(data, playlistID: playlistID)
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func handleLoadFailure(playlistID: String) {
        guard loadedID == playlistID else { return }
        loadedID = nil
    }

    private func applyLoadedPlaylistData(_ data: Data, playlistID: String) {
        guard loadedID == playlistID else { return }
        loadedPlaylist = try? JSONDecoder().decode(Playlist.self, from: data)
        fallbackSongs = loadedPlaylist?.songListDTOs ?? SongPayloadDecoder.decodeSongs(from: data) ?? fallbackSongs
        refreshFallbackArtwork()
    }

    func refreshFallbackArtwork() {
        var urls: [URL] = []
        if let loadedPlaylist {
            urls.append(contentsOf: Self.extractMosaicURLs(from: loadedPlaylist))
        }
        urls.append(contentsOf: Self.extractArtworkURLs(fromSongs: fallbackSongs))
        artworkURLs = Array(urls.prefix(4))
    }

    private static func extractMosaicURLs(from playlist: Playlist) -> [URL] {
        let mediaURLs = playlist.mosaicMedia?.compactMap { media -> URL? in
            Playlist.mediaURL(from: media, variant: .card)
        } ?? []
        if !mediaURLs.isEmpty { return Playlist.uniqueURLs(mediaURLs, limit: 4) }
        return extractArtworkURLs(fromSongs: playlist.songListDTOs ?? [])
    }

    private static func extractArtworkURLs(fromSongs songs: [Song]) -> [URL] {
        Playlist.songArtworkURLs(songs, limit: 4)
    }
}
