import Foundation
import Observation

/// Songs picked from search results, newest first. Search shows them as
/// "Recently Searched" while the field is open and empty, as Apple Music does,
/// so a song you went looking for is one tap away the next time.
@MainActor
@Observable
final class RecentSearchesStore {
    static let shared = RecentSearchesStore()
    static let storageKey = "nk.recentSearches.songs.v1"
    static let limit = 15

    private(set) var songs: [Song] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Moves `song` to the front, keeping one entry per song.
    func record(_ song: Song) {
        var next = songs.filter { $0.id != song.id }
        next.insert(song, at: 0)
        songs = Array(next.prefix(Self.limit))
        save()
    }

    func remove(_ song: Song) {
        guard songs.contains(where: { $0.id == song.id }) else { return }
        songs.removeAll { $0.id == song.id }
        save()
    }

    func clear() {
        guard !songs.isEmpty else { return }
        songs = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Song].self, from: data)
        else { return }
        songs = Array(decoded.prefix(Self.limit))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(songs) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
