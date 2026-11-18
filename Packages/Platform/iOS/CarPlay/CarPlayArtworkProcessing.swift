#if canImport(CarPlay) && canImport(UIKit)
    import UIKit

    /// Prepares artwork for CarPlay list rows.
    nonisolated enum CarPlayArtworkProcessing {
        /// Square-crops and downscales `image` off the main actor: both redraw
        /// the full bitmap, and a CarPlay list loads one per row.
        @concurrent
        static func squareArtwork(
            _ image: UIImage?,
            maxPixel: CGFloat,
            render: @Sendable (UIImage, CGFloat) -> UIImage = { image, maxPixel in
                image.croppedToSquare().downscaled(maxPixel: maxPixel)
            }
        ) async -> UIImage? {
            image.map { render($0, maxPixel) }
        }
    }
#endif
