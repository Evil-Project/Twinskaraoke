import Foundation

nonisolated enum AccountSessionEvents {
    // Keep the existing notification identifier for companion compatibility.
    static let changed = Notification.Name("KaraokeWatchSessionChanged")
}

extension Notification.Name {
  nonisolated static let karaokeSessionExpired = Notification.Name("KaraokeSessionExpired")
}
