import Foundation
import SDWebImage
import SwiftUI
import UIKit

/// Synchronous memory-cache lookup for artwork, used to skip `WebImage`'s
/// unavoidable placeholder frame.
///
/// `WebImage.body` checks `imageManager.image != nil` *before* it calls
/// `setupInitialState()` (which is what starts the load). So even when the
/// image is already in the memory cache and the load completes synchronously,
/// the assignment lands after the current body evaluation has already taken
/// the placeholder branch — SwiftUI schedules a second pass, and the row paints
/// grey for at least one frame. During a fast flick that one frame per row is
/// exactly the placeholder that remains visible.
///
/// Reading the memory cache directly during `body` sidesteps that: if the
/// bitmap is already resident we render it immediately, in the same pass.
///
/// This is only valid because the app installs no `cacheKeyFilter` and no
/// image transformer, so SDWebImage's cache key is the URL's absolute string.
/// If either is ever added, this lookup must go through
/// `SDWebImageManager.shared.cacheKey(for:)` instead.
enum ArtworkMemoryCache {
    /// Returns the decoded image if it is already resident in memory.
    ///
    /// Deliberately memory-only: a disk hit would touch the filesystem, and
    /// doing that synchronously during `body` would stall the scroll — far
    /// worse than the placeholder it would avoid.
    static func image(for url: URL?) -> Image? {
        guard let url else { return nil }
        let cached = SDImageCache.shared.imageFromMemoryCache(forKey: url.absoluteString)
        return cached.flatMap(renderableImage)
    }

    /// Mirrors `WebImage.configure(image:)`.
    ///
    /// SDWebImageSwiftUI deliberately prefers `Image(decorative:scale:
    /// orientation:)` over `Image(uiImage:)`: with an EXIF-oriented UIImage,
    /// SwiftUI's `.aspectRatio` misbehaves, and the UIImage initialiser has a
    /// separate bug inside tab bar items. The fast path has to render
    /// identically to the async path or images would subtly shift when one
    /// took over from the other.
    ///
    /// Animated and vector images fall through to `WebImage`: animation needs
    /// its player, and rasterising a vector here would mean drawing into a
    /// bitmap context during `body`.
    private static func renderableImage(_ image: UIImage) -> Image? {
        guard !image.sd_isAnimated, !image.sd_isVector, let cgImage = image.cgImage else {
            return nil
        }
        return Image(
            decorative: cgImage,
            scale: image.scale,
            orientation: swiftUIOrientation(image.imageOrientation)
        )
    }

    private static func swiftUIOrientation(_ orientation: UIImage.Orientation) -> Image.Orientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

// Measured on device 2026-08-02 with a temporary hit-rate probe: 92–99% of rows
// take this fast path once the cache is warm (25% on a cold start, and dipping
// to ~75% only while images are still downloading). That is why the two
// structural rewrites once planned here — persisting pre-decoded assets, and
// replacing `WebImage` in lists with a UIKit collection view — were dropped:
// decode is not on the critical path, and the collection view's only real
// benefit was the synchronous assignment this already provides.
