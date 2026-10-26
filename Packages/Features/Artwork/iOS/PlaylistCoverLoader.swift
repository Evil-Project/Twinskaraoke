import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class PlaylistCoverLoader {
    var artworkURLs: [URL] = []
    private var loadedID: String?
    private var fallbackSongs: [Song] = []
    private var loadedPlaylist: Playlist?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let fetchData: @MainActor (String) async throws -> Data

    init(fetchData: @escaping @MainActor (String) async throws -> Data = {
        try await KaraokeAPIClient.playlistDetailData(id: $0)
    }) {
        self.fetchData = fetchData
    }

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

        let fetchData = self.fetchData
        loadTask = Task { [weak self] in
            guard let data = try? await fetchData(playlistID) else {
                guard !Task.isCancelled else { return }
                self?.handleLoadFailure(playlistID: playlistID)
                return
            }
            let decoded = await Self.decodeArtworkPayload(data)
            guard !Task.isCancelled else { return }
            guard decoded.playlist != nil || decoded.songs != nil else {
                self?.handleLoadFailure(playlistID: playlistID)
                return
            }
            self?.applyDecodedArtwork(decoded, playlistID: playlistID)
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func handleLoadFailure(playlistID: String) {
        guard loadedID == playlistID else { return }
        loadedID = nil
    }

    private struct DecodedArtworkPayload: Sendable {
        let playlist: Playlist?
        let songs: [Song]?
    }

    /// Decodes off the main actor; callers hop back to main only to assign results.
    @concurrent private static func decodeArtworkPayload(_ data: Data) async -> DecodedArtworkPayload {
        let playlist = try? JSONDecoder().decode(Playlist.self, from: data)
        let songs = playlist?.songListDTOs ?? SongPayloadDecoder.decodeSongs(from: data)
        return DecodedArtworkPayload(playlist: playlist, songs: songs)
    }

    private func applyDecodedArtwork(_ decoded: DecodedArtworkPayload, playlistID: String) {
        guard loadedID == playlistID else { return }
        loadedPlaylist = decoded.playlist
        fallbackSongs = decoded.songs ?? fallbackSongs
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
