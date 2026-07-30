import Combine
import Foundation

/// Songs played on this watch, most recent first.
///
/// Deliberately watch-local and not part of the session bridge: it answers
/// "what was I just listening to on my wrist", which is a different question
/// from the phone's recently-played playlists, and it stays useful while
/// signed out.
@MainActor
final class RecentlyPlayedStore: ObservableObject {
    static let shared = RecentlyPlayedStore()

    @Published private(set) var songs: [Song] = []

    /// Small enough that the whole list stays a glance rather than a scroll,
    /// and that re-encoding it on every track change stays cheap.
    private let limit = 10
    private let storageKey = "nk.watch.recentlyPlayed"
    private let defaults = UserDefaults.standard

    /// History is device state that outlives a launch, so a UI test would
    /// inherit whatever the previous run played and see a different Home
    /// layout. Kept empty there, the same way `HomeViewModel` swaps in fixtures.
    private let isEnabled = !AppRuntime.isUITestMode

    private init() {
        guard isEnabled else { return }
        load()
    }

    func record(_ song: Song) {
        guard isEnabled else { return }
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
