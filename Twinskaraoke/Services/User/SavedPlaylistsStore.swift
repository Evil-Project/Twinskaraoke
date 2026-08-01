import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class SavedPlaylistsStore {
    static let shared = SavedPlaylistsStore()
    private static let storageKey = "nk.savedPlaylists.v1"
    private(set) var playlists: [Playlist] = []
    // O(1) membership cache for isSaved, which is called per visible
    // playlist count label on every publish.
    private var savedIDs: Set<String> = []
    private init() {
        load()
    }

    func isSaved(_ playlist: Playlist) -> Bool {
        savedIDs.contains(playlist.id)
    }

    func add(_ playlist: Playlist) {
        guard !playlist.isFavorites else { return }
        if isSaved(playlist) { return }
        playlists.insert(playlist, at: 0)
        savedIDs.insert(playlist.id)
        RecentlyAddedTracker.shared.bump(playlist.id)
        save()
    }

    func remove(id: String) {
        playlists.removeAll { $0.id == id }
        savedIDs.remove(id)
        save()
    }

    func toggle(_ playlist: Playlist) {
        if isSaved(playlist) { remove(id: playlist.id) } else { add(playlist) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
            savedIDs = Set(decoded.map(\.id))
        }
    }

    private func save() {
        // Persist lightweight metadata only: songListDTOs embeds full song
        // arrays and stays in memory. load() still decodes older blobs that
        // include the songs.
        let stripped = playlists.map {
            Playlist(
                id: $0.id,
                name: $0.name,
                songCount: $0.songCount,
                media: $0.media,
                mosaicMedia: $0.mosaicMedia,
                songListDTOs: nil,
                isPersonal: $0.isPersonal
            )
        }
        if let data = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
