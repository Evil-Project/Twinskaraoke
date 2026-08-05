import AppKit
import SwiftUI

/// In-memory + disk artwork cache for the Mac app.
///
/// Mirrors `TVImageCache` rather than pulling in SDWebImage: the Mac target
/// only needs artwork for rows, the sidebar and the player bar, so keeping the
/// dependency out means this target links nothing beyond system frameworks.
/// The lock is confined to the synchronous `fetchPlan`/`finishFetch` helpers —
/// under Swift 6 holding an `NSLock` across an `await` is a hard error.
final class MacImageCache: @unchecked Sendable {
    static let shared = MacImageCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let disk = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    /// Guards `inFlight` and `failures` (NSCache/URLCache are already thread-safe).
    private let stateLock = NSLock()
    private var inFlight: [NSURL: Task<NSImage?, Never>] = [:]
    /// Short-lived negative cache so scrolling doesn't hammer a dead host.
    private var failures: [NSURL: Date] = [:]
    private static let negativeTTL: TimeInterval = 30

    private init() {
        memory.countLimit = 400
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    /// Synchronous lookup so a view can render artwork on first layout instead
    /// of flashing a placeholder for one frame.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) { return cached }

        let request = URLRequest(url: url)
        if let stored = disk.cachedResponse(for: request), let image = NSImage(data: stored.data) {
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
        let task = Task<NSImage?, Never> { [memory, disk] in
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data)
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

/// Drop-in cached async image that serves repeated loads from `MacImageCache`.
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
        // Seed from the memory cache so an already-loaded image renders on the
        // first frame rather than flashing the placeholder.
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
            guard image == nil, let url else { return }
            image = await MacImageCache.shared.image(for: url)
        }
    }
}

/// Square artwork tile with the app's standard placeholder, used by rows, the
/// grid cards and the player bar so they stay visually identical.
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
