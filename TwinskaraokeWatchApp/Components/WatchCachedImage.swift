import SwiftUI

/// In-memory + disk image cache for the watch app (no SDWebImage on this target).
final class WatchImageCache {
    static let shared = WatchImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    // Dedicated, bounded disk cache instead of the default shared URLCache.
    private let disk = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
    /// Guards `inFlight` and `failures` (NSCache/URLCache are already thread-safe).
    private let stateLock = NSLock()
    /// Fetches currently in flight, so a prefetcher and a visible row asking
    /// for the same URL share one request instead of racing two.
    private var inFlight: [NSURL: Task<UIImage?, Never>] = [:]
    /// Short-lived negative cache for failed URLs so scrolling does not
    /// hammer a dead host on every row re-entry.
    private var failures: [NSURL: Date] = [:]
    private static let negativeTTL: TimeInterval = 30

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 32 * 1024 * 1024
    }

    /// Synchronous memory-cache lookup used to seed views without a placeholder frame.
    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) { return cached }

        let request = URLRequest(url: url)
        if let stored = disk.cachedResponse(for: request),
           let image = UIImage(data: stored.data) {
            memory.setObject(image, forKey: key, cost: stored.data.count)
            return image
        }

        switch fetchPlan(for: key, request: request) {
        case .knownFailure:
            return nil
        case .coalesce(let task):
            // Coalesce with the caller already fetching this URL.
            _ = await task.value
            return memory.object(forKey: key)
        case .start(let task):
            let image = await task.value
            finishFetch(for: key, image: image)
            return image
        }
    }

    /// How `image(for:)` should proceed for a URL, decided under the lock.
    private enum FetchPlan {
        case knownFailure
        case coalesce(Task<UIImage?, Never>)
        case start(Task<UIImage?, Never>)
    }

    /// Synchronous critical section (lock is never held across an `await`):
    /// returns the negative-cache / in-flight state for `key`, registering a
    /// new fetch task when neither applies.
    private func fetchPlan(for key: NSURL, request: URLRequest) -> FetchPlan {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < Self.negativeTTL {
            return .knownFailure
        }
        if let task = inFlight[key] {
            return .coalesce(task)
        }
        let task = Task<UIImage?, Never> { [memory, disk] in
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data)
            else { return nil }
            memory.setObject(image, forKey: key, cost: data.count)
            disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            return image
        }
        inFlight[key] = task
        return .start(task)
    }

    /// Synchronous critical section: clears the in-flight entry and records
    /// a short-lived negative-cache entry when the fetch failed.
    private func finishFetch(for key: NSURL, image: UIImage?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        inFlight[key] = nil
        guard image == nil else { return }
        if failures.count > 256 {
            let now = Date()
            failures = failures.filter { now.timeIntervalSince($0.value) < Self.negativeTTL }
        }
        failures[key] = Date()
    }

    /// Whether `url` is inside the negative-cache window (test hook).
    func isKnownFailure(for url: URL) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let failedAt = failures[url as NSURL] else { return false }
        return Date().timeIntervalSince(failedAt) < Self.negativeTTL
    }
}

/// Drop-in replacement for AsyncImage that serves repeated loads from WatchImageCache,
/// avoiding re-fetch/re-decode flicker when rows re-enter the view hierarchy.
struct WatchCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { WatchImageCache.shared.cachedImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            // URL changed: drop the previous artwork, re-seeding from the
            // memory cache exactly like the initial State value in init.
            image = WatchImageCache.shared.cachedImage(for: url)
            let loaded = await WatchImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
