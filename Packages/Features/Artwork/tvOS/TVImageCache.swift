import SwiftUI
import UIKit

/// In-memory + disk image cache for the tvOS app (no SDWebImage on this target).
/// Mirrors the watch app's cache so repeated artwork loads don't re-fetch or
/// flicker when focusable cards re-enter the view hierarchy.
final class TVImageCache {
    static let shared = TVImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let disk = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    /// Guards `inFlight` and `failures` (NSCache/URLCache are already thread-safe).
    private let stateLock = NSLock()
    private var inFlight: [NSURL: Task<UIImage?, Never>] = [:]
    /// Short-lived negative cache so scrolling doesn't hammer a dead host.
    private var failures: [NSURL: Date] = [:]
    private static let negativeTTL: TimeInterval = 30

    private init() {
        memory.countLimit = 400
        memory.totalCostLimit = 64 * 1024 * 1024
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
            memory.setObject(image, forKey: key, cost: Self.memoryCost(for: image, fallback: stored.data.count))
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
            memory.setObject(image, forKey: key, cost: Self.memoryCost(for: image, fallback: data.count))
            disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            return image
        }
        inFlight[key] = task
        return .start(task)
    }

    private static func memoryCost(for image: UIImage, fallback: Int) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let scale = max(image.scale, 1)
        let pixelWidth = Int(image.size.width * scale)
        let pixelHeight = Int(image.size.height * scale)
        let estimatedCost = pixelWidth * pixelHeight * 4
        return estimatedCost > 0 ? estimatedCost : fallback
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

/// Drop-in cached async image that serves repeated loads from TVImageCache.
struct TVRemoteImage<Content: View, Placeholder: View>: View {
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
        _image = State(initialValue: url.flatMap { TVImageCache.shared.cachedImage(for: $0) })
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
            image = TVImageCache.shared.cachedImage(for: url)
            let loaded = await TVImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
