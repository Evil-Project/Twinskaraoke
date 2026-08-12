import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

nonisolated struct ArtworkPalette: Equatable {
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var quaternary: Color

    init(primary: Color, secondary: Color, tertiary: Color, quaternary: Color) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.quaternary = quaternary
    }

    static let placeholder = ArtworkPalette(
        primary: .appPlaceholderPrimary,
        secondary: .appPlaceholderSecondary,
        tertiary: .appPlaceholderTertiary,
        quaternary: .appPlaceholderQuaternary
    )
    #if canImport(UIKit)
        init(image: UIImage) {
            let samples = ArtworkPalette.dominantColors(image: image, count: 4)
            // Non-empty by construction: the placeholder supplies four colors.
            let safe = samples.isEmpty ? Self.placeholder.allColors() : samples
            // Cycle rather than concatenating a fixed number of copies.
            // `safe + safe + safe` only reaches four entries when `safe` holds
            // at least two colors, and a near-monochrome cover (or one whose
            // top buckets all collapse under the dedup filter in
            // dominantColors) can yield exactly one — leaving the fourth
            // subscript out of range.
            var arr: [UIColor] = []
            arr.reserveCapacity(4)
            while arr.count < 4 {
                arr.append(safe[arr.count % safe.count])
            }
            primary = Color(arr[0])
            secondary = Color(arr[1])
            tertiary = Color(arr[2])
            quaternary = Color(arr[3])
        }
    #endif
    #if canImport(UIKit)
        func allColors() -> [UIColor] {
            [primary, secondary, tertiary, quaternary].map { UIColor($0) }
        }

        private static func dominantColors(image: UIImage, count: Int) -> [UIColor] {
            let size = CGSize(width: 32, height: 32)
            let width = Int(size.width)
            let height = Int(size.height)
            // Draw into a context whose layout we chose, rather than sampling
            // whatever one of the UIKit convenience renderers happened to
            // produce. Neither `UIGraphicsBeginImageContextWithOptions` nor
            // `UIGraphicsImageRenderer` promises a channel order, and on iOS
            // both hand back BGRA — so the byte walk below, which reads the
            // first three bytes as R, G and B, was returning every palette with
            // red and blue exchanged. `premultipliedLast | byteOrder32Big` is
            // RGBA, and sRGB at 8 bits per component keeps the offsets honest
            // on wide-gamut displays.
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  )
            else { return [] }
            UIGraphicsPushContext(context)
            // Drawn without the UIKit flip, so this lands vertically mirrored.
            // Irrelevant: what follows is a histogram over every sampled pixel,
            // and it does not care where any of them sat.
            image.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
            guard let base = context.data else { return [] }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let bpp = 4
            let rowBytes = context.bytesPerRow
            let byteCount = rowBytes * height
            var buckets: [UInt32: (count: Int, saturation: CGFloat, brightness: CGFloat)] = [:]
            for y in stride(from: 0, to: Int(size.height), by: 2) {
                for x in stride(from: 0, to: Int(size.width), by: 2) {
                    let offset = y * rowBytes + x * bpp
                    guard offset >= 0, offset + 2 < byteCount else { continue }
                    let r = bytes[offset]
                    let g = bytes[offset + 1]
                    let b = bytes[offset + 2]
                    let key = (UInt32(r >> 3) << 10) | (UInt32(g >> 3) << 5) | UInt32(b >> 3)
                    let color = UIColor(
                        red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1
                    )
                    var h: CGFloat = 0
                    var s: CGFloat = 0
                    var v: CGFloat = 0
                    var a: CGFloat = 0
                    color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                    if v < 0.08 || v > 0.97 { continue }
                    let existing = buckets[key]
                    buckets[key] = ((existing?.count ?? 0) + 1, s, v)
                }
            }
            let ranked =
                buckets
                    .map {
                        (key: UInt32, value: (count: Int, saturation: CGFloat, brightness: CGFloat)) -> (
                            UInt32, Double
                        ) in
                        let score = Double(value.count) * pow(Double(value.saturation) + 0.1, 0.6)
                        return (key, score)
                    }
                    .sorted { $0.1 > $1.1 }
                    .prefix(count * 4)
            var picked: [UIColor] = []
            for (key, _) in ranked {
                let r = CGFloat((key >> 10) & 0x1F) / 31
                let g = CGFloat((key >> 5) & 0x1F) / 31
                let b = CGFloat(key & 0x1F) / 31
                let candidate = UIColor(red: r, green: g, blue: b, alpha: 1)
                if picked.contains(where: { $0.distance(to: candidate) < 0.18 }) { continue }
                picked.append(candidate)
                if picked.count >= count { break }
            }
            return picked
        }
    #endif
}

#if canImport(UIKit)

    nonisolated fileprivate extension UIColor {
        func distance(to other: UIColor) -> CGFloat {
            var r1: CGFloat = 0
            var g1: CGFloat = 0
            var b1: CGFloat = 0
            var a1: CGFloat = 0
            var r2: CGFloat = 0
            var g2: CGFloat = 0
            var b2: CGFloat = 0
            var a2: CGFloat = 0
            getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let dr = r1 - r2
            let dg = g1 - g2
            let db = b1 - b2
            return sqrt(dr * dr + dg * dg + db * db)
        }
    }
#endif
