import SwiftUI
final class WatchImageCache {
    static let shared = WatchImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let disk = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
    private let stateLock = NSLock()
    private var inFlight: [NSURL: Task<UIImage?, Never>] = [:]
    private var failures: [NSURL: Date] = [:]
    private static let negativeTTL: TimeInterval = 30

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 32 * 1024 * 1024
    }
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
            _ = await task.value
            return memory.object(forKey: key)
        case .start(let task):
            let image = await task.value
            finishFetch(for: key, image: image)
            return image
        }
    }
    private enum FetchPlan {
        case knownFailure
        case coalesce(Task<UIImage?, Never>)
        case start(Task<UIImage?, Never>)
    }
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

}
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
            image = WatchImageCache.shared.cachedImage(for: url)
            let loaded = await WatchImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
