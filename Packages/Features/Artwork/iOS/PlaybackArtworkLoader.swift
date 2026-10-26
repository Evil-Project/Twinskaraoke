import Foundation
import SDWebImage
import UIKit

/// Owns image requests, processing, warmups and their cancellation, independently of audio.
@MainActor
final class PlaybackArtworkLoader {
    private var request: (any SDWebImageOperation)?
    private var processing: Task<Void, Never>?
    private var warmups: [String: any SDWebImageOperation] = [:]
    private var warmedAt: [String: Date] = [:]
    private var generation = 0
    private nonisolated(unsafe) static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    func load(_ url: URL, completion: @escaping @MainActor (UIImage) -> Void) {
        cancel()
        let generation = generation
        if let cached = Self.cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        request = SDWebImageManager.shared.loadImage(
            with: url, options: [], context: ImageCacheConfig.memoryAndDiskCacheContext, progress: nil
        ) { [weak self] image, _, _, _, _, _ in
            guard let image else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.processing = Task.detached(priority: .userInitiated) { [weak self] in
                    guard !Task.isCancelled else { return }
                    let square = image.croppedToSquare().downscaled(maxPixel: 600)
                    guard !Task.isCancelled else { return }
                    let cost = Int(square.size.width * square.size.height * square.scale * square.scale * 4)
                    Self.cache.setObject(square, forKey: url as NSURL, cost: cost)
                    await MainActor.run { [weak self] in
                        guard let self, self.generation == generation else { return }
                        completion(square)
                    }
                }
            }
        }
    }

    func warm(_ urls: [URL]) {
        let now = Date()
        warmedAt = warmedAt.filter { now.timeIntervalSince($0.value) < 60 }
        for url in urls {
            let key = url.absoluteString
            guard warmedAt[key] == nil, warmups[key] == nil else { continue }
            warmedAt[key] = now
            warmups[key] = SDWebImageManager.shared.loadImage(
                with: url, options: [.highPriority], context: ImageCacheConfig.visibleImageContext, progress: nil
            ) { [weak self] _, _, _, _, _, _ in
                Task { @MainActor [weak self] in _ = self?.warmups.removeValue(forKey: key) }
            }
        }
    }

    func cancel() {
        generation &+= 1
        request?.cancel()
        request = nil
        processing?.cancel()
        processing = nil
    }

    func cancelWarmups() {
        warmups.values.forEach { $0.cancel() }
        warmups.removeAll()
    }

    func resetWarmups() {
        cancelWarmups()
        warmedAt.removeAll()
    }

    func clearCache() { Self.cache.removeAllObjects() }

    isolated deinit {
        request?.cancel()
        processing?.cancel()
        warmups.values.forEach { $0.cancel() }
    }
}
