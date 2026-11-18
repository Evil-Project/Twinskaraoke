/// How the radio player arranges itself for a canvas and a text size.
///
/// The canvas decision is the music player's own (`PlayerLayoutMetrics.usesPadLayout`),
/// so both players switch to their wide layouts at the same width and Slide
/// Over or a half-width Split View window keeps the phone column. Pure values,
/// so `nonisolated`: tests build them as `@Test` arguments.
nonisolated struct RadioPlayerLayoutStyle: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        /// The phone column: artwork, title row, stop button, volume, toolbar.
        case compact
        /// The music player's lyrics-off iPad layout: a larger artwork in a
        /// centred column with the pad paddings, instead of a phone column
        /// stranded in the middle of the canvas.
        case wide
    }

    let arrangement: Arrangement
    /// Puts "N listening" on its own line under "LIVE RADIO". On one line at an
    /// accessibility size the three pieces split the title column and each
    /// truncates.
    let stacksLiveMeta: Bool

    init(arrangement: Arrangement, stacksLiveMeta: Bool) {
        self.arrangement = arrangement
        self.stacksLiveMeta = stacksLiveMeta
    }

    init(usesPadLayout: Bool, isAccessibilitySize: Bool) {
        self.init(
            arrangement: usesPadLayout ? .wide : .compact,
            stacksLiveMeta: Self.stacksLiveMeta(isAccessibilitySize: isAccessibilitySize)
        )
    }

    static func stacksLiveMeta(isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
    }
}
