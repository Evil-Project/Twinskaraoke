import Foundation
import Observation
@MainActor
@Observable
final class RecentlyPlayedStore {
    static let shared = RecentlyPlayedStore()

    private(set) var songs: [Song] = []
    private let limit = 10
    private let storageKey = "nk.watch.recentlyPlayed"
    private let defaults = UserDefaults.standard

    private init() {
        load()
    }

    func record(_ song: Song) {
        var updated = songs
        updated.removeAll { $0.id == song.id }
        updated.insert(song, at: 0)
        if updated.count > limit {
            updated.removeLast(updated.count - limit)
        }
        songs = updated
        save()
    }

    func clear() {
        songs = []
        defaults.removeObject(forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Song].self, from: data)
        else { return }
        songs = Array(decoded.prefix(limit))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(songs) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
