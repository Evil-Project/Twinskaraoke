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
}
