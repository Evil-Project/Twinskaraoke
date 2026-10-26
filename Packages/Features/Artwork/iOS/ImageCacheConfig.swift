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
        cfg.maxMemoryCount = 1000
        cfg.maxDiskSize = UInt(CacheManager.imageCacheLimit)
        cfg.shouldCacheImagesInMemory = true
        cfg.shouldUseWeakMemoryCache = true
        cfg.maxDiskAge = 90 * 24 * 60 * 60
        let dl = SDWebImageDownloader.shared

        dl.config.maxConcurrentDownloads = 6
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
