import Foundation
import Observation

@MainActor
@Observable
final class PlaylistSongCountStore {
    static let shared = PlaylistSongCountStore()

    private var resolvedCounts: [String: Int] = [:]
    private var loadingIDs: Set<String> = []
    private var generations: [String: UInt64] = [:]

    func displayedCount(for playlist: Playlist, prefersDetailCount: Bool = false) -> Int? {
        if let resolved = resolvedCounts[playlist.id] {
            return resolved
        }
        if playlist.isFavorites {
            return playlist.songCount
        }
        let needsDetail = Self.needsDetailCount(
            for: playlist,
            isSaved: SavedPlaylistsStore.shared.isSaved(playlist)
        )
        if prefersDetailCount && needsDetail {
            return nil
        }
        if playlist.songCount > 0 {
            return playlist.songCount
        }
        let embeddedCount = playlist.songListDTOs?.count ?? 0
        return embeddedCount > 0 ? embeddedCount : nil
    }

    func loadIfNeeded(for playlist: Playlist, forceDetailCount: Bool = false) {
        guard !playlist.isFavorites else { return }
        let isSavedPlaylist = SavedPlaylistsStore.shared.isSaved(playlist)
        guard forceDetailCount
            || Self.needsDetailCount(for: playlist, isSaved: isSavedPlaylist)
        else { return }
        guard resolvedCounts[playlist.id] == nil else { return }
        guard !loadingIDs.contains(playlist.id) else { return }
        loadingIDs.insert(playlist.id)
        let generation = generations[playlist.id, default: 0]
        Task {
            let count: Int?
            do {
                count = try await KaraokeAPIClient.playlistSongCount(id: playlist.id)
            } catch {
                count = nil
            }

            loadingIDs.remove(playlist.id)
            if let count, generations[playlist.id, default: 0] == generation {
                resolvedCounts[playlist.id] = count
            }
        }
    }

    func recordResolvedCount(_ count: Int, for playlistID: String) {
        resolvedCounts[playlistID] = max(0, count)
    }

    func invalidate(playlistID: String) {
        generations[playlistID, default: 0] &+= 1
        resolvedCounts.removeValue(forKey: playlistID)
    }

    static func needsDetailCount(for playlist: Playlist, isSaved: Bool) -> Bool {
        guard !playlist.isFavorites else { return false }
        return playlist.isPersonal || isSaved || playlist.songCount == 0
    }
}
