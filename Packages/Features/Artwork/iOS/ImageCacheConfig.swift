import Foundation
import SDWebImage
#if canImport(UIKit)
    import UIKit
#endif

enum ImageCacheConfig {
    private static var didApply = false

    static let memoryAndDiskCacheContext: [SDWebImageContextOption: Any] = [
        .queryCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
        .storeCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
    ]

    static let visibleImageContext: [SDWebImageContextOption: Any] = [
        .queryCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
        .storeCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
        .imageDecodeOptions: [SDImageCoderOption.decodeScaleFactor: 1.0],
    ]

    // Prefetch warms cache without forcing decode; decoding happens on display.
    //
    // Tried `.automatic` here to make prefetched rows display-ready. Reverted:
    // force-decoding makes SDWebImage store a decoded image rather than the
    // original bytes, and re-encoding those bytes fails — Apple's ImageIO can
    // decode WebP but cannot write it, and this app requests WebP. That spammed
    // `CGImageDestinationCreateWithData` failures on every image.
    static let prefetchContext: [SDWebImageContextOption: Any] = [
        .queryCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
        .storeCacheType: NSNumber(value: SDImageCacheType.all.rawValue),
        .imageForceDecodePolicy: NSNumber(value: SDImageForceDecodePolicy.never.rawValue),
    ]

    static func applyLimits() {
        guard !didApply else { return }
        didApply = true
        let cfg = SDImageCache.shared.config
        cfg.maxMemoryCost = 128 * 1024 * 1024
        // The count cap binds long before the cost cap for list artwork: a 48pt
        // row at @3x decodes to ~81 KB, so 240 images is only ~19 MB of the
        // 128 MB budget. Scrolling past ~240 rows evicted the earliest bitmaps
        // and forced a disk read *and* re-decode on the way back — placeholders
        // on a playlist whose bytes were already local. 1000 row thumbnails is
        // ~79 MB, still inside the cost cap, which remains the real ceiling
        // (large hero images consume it far faster and evict sooner).
        cfg.maxMemoryCount = 1000
        // Single source of truth: CacheManager.imageCacheLimit, so SDWebImage's
        // own pruning matches the limit CacheManager enforces (and the value
        // the Settings UI advertises).
        cfg.maxDiskSize = UInt(CacheManager.imageCacheLimit)
        cfg.shouldCacheImagesInMemory = true
        cfg.shouldUseWeakMemoryCache = true
        cfg.maxDiskAge = 90 * 24 * 60 * 60
        let dl = SDWebImageDownloader.shared

        dl.config.maxConcurrentDownloads = 6
        // Modifier blocks run on SDWebImage's download queue; they must be
        // @Sendable so they don't inherit main-actor isolation (which would
        // trap at runtime when invoked off the main thread).
        dl.requestModifier = SDWebImageDownloaderRequestModifier { @Sendable request in
            var r = request
            r.cachePolicy = .returnCacheDataElseLoad
            r.timeoutInterval = 15
            r.setValue("image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            return r
        }
        dl.responseModifier = SDWebImageDownloaderResponseModifier { @Sendable response in
            guard let httpResponse = response as? HTTPURLResponse,
                  let url = httpResponse.url,
                  shouldInspectArtworkResponse(url),
                  let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                  !contentType.contains("webp")
            else { return response }

            DebugLogger.log(
                "Artwork response content-type=\(contentType), status=\(httpResponse.statusCode), url=\(redactedURLString(url))",
                category: .cache
            )
            return response
        }
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main
            ) { _ in
                SDImageCache.shared.clearMemory()
            }
        #endif
    }

    static let defaultOptions: SDWebImageOptions = []

    private nonisolated static func shouldInspectArtworkResponse(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.contains("images.neurokaraoke.com")
            || (host.contains("storage.neurokaraoke.com") && url.path.contains("/cdn-cgi/image/"))
    }

    private nonisolated static func redactedURLString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? url.lastPathComponent
    }
}
