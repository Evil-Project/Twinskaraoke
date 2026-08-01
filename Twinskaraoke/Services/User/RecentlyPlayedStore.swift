import Combine
import Foundation
import SwiftUI

@MainActor
final class RecentlyPlayedStore: ObservableObject {
    static let shared = RecentlyPlayedStore()
    private static let storageKey = "nk.recentlyPlayed.playlists.v1"
    private static let limit = 20
    @Published private(set) var playlists: [Playlist] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(_ playlist: Playlist) {
        guard !playlist.isSessionOwned else { return }
        var next = playlists.filter { $0.id != playlist.id }
        next.insert(playlist, at: 0)
        if next.count > Self.limit { next = Array(next.prefix(Self.limit)) }
        playlists = next
        save()
    }

    func reset() {
        playlists = []
        defaults.removeObject(forKey: Self.storageKey)
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
