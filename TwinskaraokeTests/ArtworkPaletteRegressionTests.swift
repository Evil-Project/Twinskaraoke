import Foundation
import Testing
import UIKit
@testable import Twinskaraoke

@Suite("Artwork palette")
struct ArtworkPaletteRegressionTests {
    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Compares in RGB space rather than by `UIColor` equality, which also
    /// takes the color space into account and so can report two visually
    /// identical colors as different after a `Color` round-trip.
    private func rgbDistance(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        lhs.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        rhs.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return ((r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    @Test("A single dominant color still fills all four palette slots")
    func singleDominantColorDoesNotTrapOnFourthSlot() {
        // A solid mid-gray cover collapses to exactly one bucket in
        // dominantColors. The old padding (`safe + safe + safe`) produced only
        // three entries in that case, so reading the fourth trapped with
        // "Index out of range".
        let palette = ArtworkPalette(image: solidImage(.gray))
        let colors = palette.allColors()

        #expect(colors.count == 4)
        // One sample cycled into every slot, so all four agree.
        for color in colors {
            #expect(rgbDistance(color, colors[0]) < 0.01)
        }
    }

    @Test("Near-black and near-white covers fall back to the placeholder")
    func fullyFilteredImageFallsBackToPlaceholder() {
        // Every pixel is discarded by the brightness filter, so dominantColors
        // returns nothing and the placeholder supplies all four colors.
        let expected = ArtworkPalette.placeholder.allColors()
        for color in [UIColor.black, UIColor.white] {
            let actual = ArtworkPalette(image: solidImage(color)).allColors()
            #expect(actual.count == 4)
            for (index, component) in expected.enumerated() {
                #expect(rgbDistance(actual[index], component) < 0.01)
            }
        }
    }

    @Test("A multi-color cover fills the slots with distinct colors")
    func multiColorImageFillsFourSlots() {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            // Explicit RGB, not system colors: dominantColors discards anything
            // with HSV brightness above 0.97, and most system colors peg a
            // channel at 1.0. These four sit inside the brightness window and
            // are far enough apart to survive the near-duplicate filter. They
            // are also stable across OS versions, unlike the dynamic system
            // palette.
            let colors: [UIColor] = [
                UIColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),
                UIColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1),
                UIColor(red: 0.20, green: 0.30, blue: 0.85, alpha: 1),
                UIColor(red: 0.85, green: 0.75, blue: 0.15, alpha: 1),
            ]
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(
                    CGRect(x: 0, y: CGFloat(index) * 16, width: 64, height: 16)
                )
            }
        }

        let palette = ArtworkPalette(image: image)
        let colors = palette.allColors()
        #expect(colors.count == 4)
        // Distinct slots: this is what separates a genuine four-color
        // extraction from the single-color path cycling one sample.
        for i in colors.indices {
            for j in colors.indices where j > i {
                #expect(rgbDistance(colors[i], colors[j]) > 0.05)
            }
        }
        #expect(palette != ArtworkPalette.placeholder)
    }
}
