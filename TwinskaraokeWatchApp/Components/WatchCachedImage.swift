import SwiftUI

/// In-memory + disk image cache for the watch app (no SDWebImage on this target).
final class WatchImageCache {
    static let shared = WatchImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let disk = URLCache.shared

    private init() {}

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
            memory.setObject(image, forKey: key)
            return image
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data)
        else { return nil }

        memory.setObject(image, forKey: key)
        disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return image
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
            let loaded = await WatchImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
