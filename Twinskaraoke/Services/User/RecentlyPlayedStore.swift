import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class RecentlyPlayedStore {
    static let shared = RecentlyPlayedStore()
    private static let storageKey = "nk.recentlyPlayed.playlists.v1"
    private static let limit = 20
    private(set) var playlists: [Playlist] = []
    private init() {
        if ProcessInfo.processInfo.arguments.contains("-UITestResetRecentlyPlayed") {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
        load()
    }

    func record(_ playlist: Playlist) {
        var next = playlists.filter { $0.id != playlist.id }
        next.insert(playlist, at: 0)
        if next.count > Self.limit { next = Array(next.prefix(Self.limit)) }
        playlists = next
        save()
    }

    func reset() {
        playlists = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    private func save() {
        // Persist lightweight metadata only: songListDTOs embeds full song
        // arrays (~1MB for a 900-song playlist) and stays in memory. load()
        // still decodes older blobs that include the songs.
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
