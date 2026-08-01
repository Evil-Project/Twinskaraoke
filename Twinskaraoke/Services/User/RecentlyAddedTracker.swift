import Foundation
import Observation

@MainActor
@Observable
final class RecentlyAddedTracker {
    static let shared = RecentlyAddedTracker()
    private static let storageKey = "nk.recentlyAddedDates.v1"
    private(set) var dates: [String: Date] = [:]
    private init() {
        load()
    }

    func date(for id: String) -> Date {
        dates[id] ?? .distantPast
    }

    func registerIfNew(_ ids: [String]) {
        // Mutate a local copy and assign once so a batch of new IDs publishes
        // a single dates change instead of one per inserted ID.
        var updated = dates
        var changed = false
        let now = Date()
        for id in ids where updated[id] == nil {
            updated[id] = now
            changed = true
        }
        guard changed else { return }
        dates = updated
        save()
    }

    func bump(_ id: String) {
        dates[id] = Date()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dates = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(dates) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
