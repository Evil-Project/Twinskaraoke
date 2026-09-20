import Foundation
import SDWebImage
import SwiftUI
import UIKit
enum ArtworkMemoryCache {
    static func image(for url: URL?) -> Image? {
        guard let url else { return nil }
        let cached = SDImageCache.shared.imageFromMemoryCache(forKey: url.absoluteString)
        return cached.flatMap(renderableImage)
    }
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
