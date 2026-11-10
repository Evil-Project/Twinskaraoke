import SwiftUI

extension View {
    /// Stops the glyphs on the player's fixed-size controls growing past the
    /// largest standard text size.
    ///
    /// These controls keep their 44pt targets at every text size, as Apple
    /// Music's do. Their glyphs are set in text styles, so at an accessibility
    /// size they outgrew those targets: the favourite star ran into the more
    /// button beside it, and the toolbar's three glyphs filled its width.
    /// The song title, the times and the lyrics still follow the text size.
    func playerControlGlyphScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Shows the view as it is where it fits, and in a scroll view where its
    /// container is too short for it.
    ///
    /// An empty state inside a fixed area (the queue sheet, the lyrics surface)
    /// is several times taller at an accessibility text size. Too tall for its
    /// area, it pushed the content above it out of the top of the sheet.
    func scrollsWhenTooTall() -> some View {
        ViewThatFits(in: .vertical) {
            self
            ScrollView {
                self
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
