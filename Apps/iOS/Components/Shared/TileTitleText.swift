import SwiftUI

/// The title under a shelf or grid tile.
///
/// One line, as on an Apple Music shelf, and two at an accessibility text
/// size: a tile is about five letters wide there, so a single line showed
/// "Evil H…" for every setlist.
struct TileTitleText: View {
    let text: String
    var font: Font = AM.Font.tileTitle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }
}
