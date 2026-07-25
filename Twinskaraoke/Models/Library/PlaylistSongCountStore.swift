import Combine
import Foundation

@MainActor
final class PlaylistSongCountStore: ObservableObject {
    static let shared = PlaylistSongCountStore()

    @Published private var resolvedCounts: [String: Int] = [:]
    private var loadingIDs: Set<String> = []

    func displayedCount(for playlist: Playlist, prefersDetailCount: Bool = false) -> Int? {
        if let resolved = resolvedCounts[playlist.id] {
            return resolved
        }
        if playlist.isFavorites {
            return playlist.songCount
        }
        if prefersDetailCount {
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

        Task {
            loadingIDs.insert(playlist.id)
            let count: Int?
            do {
                count = try await KaraokeAPIClient.playlistSongCount(id: playlist.id)
            } catch {
                count = nil
            }

            loadingIDs.remove(playlist.id)
            if let count {
                resolvedCounts[playlist.id] = count
            }
        }
    }

    func recordResolvedCount(_ count: Int, for playlistID: String) {
        resolvedCounts[playlistID] = max(0, count)
    }

    static func needsDetailCount(for playlist: Playlist, isSaved: Bool) -> Bool {
        guard !playlist.isFavorites else { return false }
        return playlist.isPersonal || isSaved || playlist.songCount == 0
    }
}
