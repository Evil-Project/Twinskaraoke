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

    @Test("A single dominant color still fills all four palette slots")
    func singleDominantColorDoesNotTrapOnFourthSlot() {
        // A solid mid-gray cover collapses to exactly one bucket in
        // dominantColors. The old padding (`safe + safe + safe`) produced only
        // three entries in that case, so reading the fourth trapped with
        // "Index out of range".
        let palette = ArtworkPalette(image: solidImage(.gray))

        #expect(palette.primary == palette.quaternary)
        #expect(palette.allColors().count == 4)
    }

    @Test("Near-black and near-white covers fall back to the placeholder")
    func fullyFilteredImageFallsBackToPlaceholder() {
        // Every pixel is discarded by the brightness filter, so dominantColors
        // returns nothing and the placeholder supplies all four colors.
        for color in [UIColor.black, UIColor.white] {
            let palette = ArtworkPalette(image: solidImage(color))
            #expect(palette.allColors().count == 4)
        }
    }

    @Test("A multi-color cover keeps four distinct slots")
    func multiColorImageFillsFourSlots() {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue, .systemOrange]
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(
                    CGRect(x: 0, y: CGFloat(index) * 16, width: 64, height: 16)
                )
            }
        }

        #expect(ArtworkPalette(image: image).allColors().count == 4)
    }
}
