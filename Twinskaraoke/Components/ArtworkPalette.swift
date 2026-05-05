import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

/// Extracts dominant colors from an image so the player background can tint
/// itself from the artwork. We sample the four corners + center for a quick,
/// dependency-free palette that's good enough for ambient backgrounds.
struct ArtworkPalette: Equatable {
  var primary: Color
  var secondary: Color
  var tertiary: Color
  var quaternary: Color
  static let placeholder = ArtworkPalette(
    primary: Color(red: 0.14, green: 0.16, blue: 0.22),
    secondary: Color(red: 0.10, green: 0.12, blue: 0.18),
    tertiary: Color(red: 0.18, green: 0.10, blue: 0.20),
    quaternary: Color(red: 0.08, green: 0.08, blue: 0.14)
  )
  #if canImport(UIKit)
    init(image: UIImage) {
      let samples = ArtworkPalette.dominantColors(image: image, count: 4)
      let safe = samples.isEmpty ? Self.placeholder.allColors() : samples
      let padded = (safe + safe + safe).prefix(4)
      let arr = Array(padded)
      self.primary = Color(arr[0])
      self.secondary = Color(arr[1])
      self.tertiary = Color(arr[2])
      self.quaternary = Color(arr[3])
    }
  #endif
  init(primary: Color, secondary: Color, tertiary: Color, quaternary: Color) {
    self.primary = primary
    self.secondary = secondary
    self.tertiary = tertiary
    self.quaternary = quaternary
  }
  #if canImport(UIKit)
    func allColors() -> [UIColor] {
      [primary, secondary, tertiary, quaternary].map { UIColor($0) }
    }
    /// Sample a small grid of pixels and pick the most-saturated, brightness-balanced
    /// distinct colors. Cheap and good enough for ambient backgrounds.
    private static func dominantColors(image: UIImage, count: Int) -> [UIColor] {
      let size = CGSize(width: 32, height: 32)
      UIGraphicsBeginImageContextWithOptions(size, false, 1)
      defer { UIGraphicsEndImageContext() }
      image.draw(in: CGRect(origin: .zero, size: size))
      guard let cg = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
        let provider = cg.dataProvider,
        let data = provider.data,
        let bytes = CFDataGetBytePtr(data)
      else { return [] }
      let bpp = max(cg.bitsPerPixel / 8, 4)
      let rowBytes = cg.bytesPerRow
      var buckets: [UInt32: (count: Int, saturation: CGFloat, brightness: CGFloat)] = [:]
      for y in stride(from: 0, to: Int(size.height), by: 2) {
        for x in stride(from: 0, to: Int(size.width), by: 2) {
          let offset = y * rowBytes + x * bpp
          let r = bytes[offset]
          let g = bytes[offset + 1]
          let b = bytes[offset + 2]
          let key = (UInt32(r >> 3) << 10) | (UInt32(g >> 3) << 5) | UInt32(b >> 3)
          let color = UIColor(
            red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
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

  extension UIColor {
    fileprivate func distance(to other: UIColor) -> CGFloat {
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
