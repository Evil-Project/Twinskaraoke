import AppKit
import ImageIO
import SwiftUI
final class MacImageCache: @unchecked Sendable {
    static let shared = MacImageCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let disk = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    private let session: URLSession
    private let stateLock = NSLock()
    private var inFlight: [NSURL: Task<NSImage?, Never>] = [:]
    private var failures: [NSURL: Date] = [:]
    private static let negativeTTL: TimeInterval = 30
    nonisolated private static let maximumEncodedImageBytes = 24 * 1024 * 1024
    nonisolated private static let maximumPixelDimension = 1_600

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        memory.countLimit = 400
        memory.totalCostLimit = 64 * 1024 * 1024
    }
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) { return cached }

        let request = URLRequest(url: url)
        if let stored = disk.cachedResponse(for: request),
           stored.data.count <= Self.maximumEncodedImageBytes,
           let image = await Task.detached(priority: .utility, operation: {
               Self.decodedImage(from: stored.data)
           }).value {
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
        case coalesce(Task<NSImage?, Never>)
        case start(Task<NSImage?, Never>)
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
        let task = Task<NSImage?, Never> { [memory, disk, session] in
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= Self.maximumEncodedImageBytes,
                  http.mimeType?.hasPrefix("image/") != false,
                  let image = await Task.detached(priority: .utility, operation: {
                      Self.decodedImage(from: data)
                  }).value
            else { return nil }
            memory.setObject(image, forKey: key, cost: Self.memoryCost(for: image, fallback: data.count))
            disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            return image
        }
        inFlight[key] = task
        return .start(task)
    }

    private static func memoryCost(for image: NSImage, fallback: Int) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage.bytesPerRow * cgImage.height
        }
        let estimated = Int(image.size.width * image.size.height * 4)
        return estimated > 0 ? estimated : fallback
    }

    nonisolated private static func decodedImage(from data: Data) -> NSImage? {
        guard data.count <= maximumEncodedImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private func finishFetch(for key: NSURL, image: NSImage?) {
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
struct MacRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { MacImageCache.shared.cachedImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let cached = MacImageCache.shared.cachedImage(for: url)
            image = cached
            guard cached == nil else { return }
            let loaded = await MacImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
struct SongArtwork: View {
    let url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        MacRemoteImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: max(10, size * 0.34)))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
