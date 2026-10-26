import UIKit

#if canImport(UIKit)
    nonisolated extension UIImage {
        func croppedToSquare() -> UIImage {
            let originalWidth = size.width
            let originalHeight = size.height
            let sideLength = min(originalWidth, originalHeight)
            let xOffset = (originalWidth - sideLength) / 2.0
            let yOffset = (originalHeight - sideLength) / 2.0
            let cropRect = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)
            guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
            return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
        }

        func downscaled(maxPixel: CGFloat) -> UIImage {
            let pixelW = size.width * scale
            let pixelH = size.height * scale
            let longest = max(pixelW, pixelH)
            guard longest > maxPixel else { return self }
            let ratio = maxPixel / longest
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
#endif
