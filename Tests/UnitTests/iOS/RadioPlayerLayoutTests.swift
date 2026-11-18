import CoreGraphics
import Testing
@testable import Twinskaraoke

/// Which radio player layout runs, as a function of the canvas and the text
/// size. The canvas decision is the music player's (`usesPadLayout`), so the
/// two players switch to their wide layouts at the same width.
@MainActor
struct RadioPlayerLayoutTests {
    @Test(arguments: [
        (usesPadLayout: false, isAccessibilitySize: false,
         expected: RadioPlayerLayoutStyle(arrangement: .compact, stacksLiveMeta: false)),
        (usesPadLayout: false, isAccessibilitySize: true,
         expected: RadioPlayerLayoutStyle(arrangement: .compact, stacksLiveMeta: true)),
        (usesPadLayout: true, isAccessibilitySize: false,
         expected: RadioPlayerLayoutStyle(arrangement: .wide, stacksLiveMeta: false)),
        (usesPadLayout: true, isAccessibilitySize: true,
         expected: RadioPlayerLayoutStyle(arrangement: .wide, stacksLiveMeta: true)),
    ])
    func theLayoutFollowsTheCanvasAndTheTextSize(
        input: (usesPadLayout: Bool, isAccessibilitySize: Bool, expected: RadioPlayerLayoutStyle)
    ) {
        let style = RadioPlayerLayoutStyle(
            usesPadLayout: input.usesPadLayout,
            isAccessibilitySize: input.isAccessibilitySize
        )
        #expect(style == input.expected)
    }

    /// A landscape iPad canvas, about what an 11" iPad gives the player.
    private static func padMetrics(accessibilityText: Bool) -> PlayerLayoutMetrics {
        PlayerLayoutMetrics(
            containerSize: CGSize(width: 1194, height: 834),
            safeTop: 24,
            safeBottom: 20,
            usesAccessibilityText: accessibilityText
        )
    }

    /// At an accessibility size the title, stop button, volume and toolbar
    /// grow, so the wide layout gives the artwork the compact layout's
    /// accessibility share of the height. At the pad artwork size the
    /// bottom rows were pushed below a short (landscape, Stage Manager) canvas.
    @Test func theWideLayoutShrinksItsArtworkAtAccessibilitySizes() {
        let regular = Self.padMetrics(accessibilityText: false)
        let accessible = Self.padMetrics(accessibilityText: true)

        #expect(RadioPlayerLayoutStyle.artworkSize(for: .wide, metrics: regular) == regular.padArtworkSize)
        #expect(RadioPlayerLayoutStyle.artworkSize(for: .wide, metrics: accessible) == accessible.radioArtSize)
        #expect(accessible.radioArtSize < accessible.padArtworkSize)
    }

    @Test func theCompactLayoutKeepsTheRadioArtworkSize() {
        for accessibilityText in [false, true] {
            let metrics = Self.padMetrics(accessibilityText: accessibilityText)
            #expect(RadioPlayerLayoutStyle.artworkSize(for: .compact, metrics: metrics) == metrics.radioArtSize)
        }
    }
}
