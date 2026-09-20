import Foundation
@MainActor
final class WatchArtworkPrefetcher {
    static let shared = WatchArtworkPrefetcher()

    private struct ActivePrefetch {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let recentWindow: TimeInterval = 45
    private var recentlyRequested: [URL: Date] = [:]
    private var tasks: [String: ActivePrefetch] = [:]

    private init() {}
    func prefetch(urls: [URL], reason: String, limit: Int = 12) {
        cancel(reason: reason)
        let requestID = UUID()
        let now = Date()
        if recentlyRequested.count > 256 {
            recentlyRequested = recentlyRequested.filter { now.timeIntervalSince($0.value) < recentWindow }
        }
        let targets = urls.prefix(limit).filter { url in
            if WatchImageCache.shared.cachedImage(for: url) != nil { return false }
            if let last = recentlyRequested[url], now.timeIntervalSince(last) < recentWindow { return false }
            recentlyRequested[url] = now
            return true
        }
        guard !targets.isEmpty else { return }
        let task = Task { [weak self] in
            for url in targets {
                if Task.isCancelled { return }
                _ = await WatchImageCache.shared.image(for: url)
            }
            guard let self, self.tasks[reason]?.id == requestID else { return }
            self.tasks[reason] = nil
        }
        tasks[reason] = ActivePrefetch(id: requestID, task: task)
    }

    func cancel(reason: String) {
        tasks[reason]?.task.cancel()
        tasks[reason] = nil
    }
}
