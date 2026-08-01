import Combine
import Foundation
import SwiftUI

@MainActor
final class SavedPlaylistsStore: ObservableObject {
    static let shared = SavedPlaylistsStore()
    private static let storageKey = "nk.savedPlaylists.v1"
    @Published private(set) var playlists: [Playlist] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isSaved(_ playlist: Playlist) -> Bool {
        playlists.contains { $0.id == playlist.id }
    }

    func add(_ playlist: Playlist) {
        guard !playlist.isSessionOwned else { return }
        if isSaved(playlist) { return }
        playlists.insert(playlist, at: 0)
        RecentlyAddedTracker.shared.bump(playlist.id)
        save()
    }

    func remove(id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func toggle(_ playlist: Playlist) {
        if isSaved(playlist) { remove(id: playlist.id) } else { add(playlist) }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded.filter { !$0.isSessionOwned }
            if playlists.count != decoded.count {
                save()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
