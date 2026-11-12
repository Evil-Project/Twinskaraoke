import SwiftUI

/// The title under a shelf or grid tile.
///
/// Two lines by default, always reserved so the tiles in a shelf stay
/// aligned: one line cut every setlist to "Evil Mini Karaoke - O…" and hid
/// its date. A song tile passes `twoLines: false` and keeps one line, as on
/// an Apple Music shelf, but still takes two at an accessibility text size,
/// where a tile is about five letters wide. A shelf of two-line tiles sizes
/// itself with `AM.Layout.mediaShelfHeight(…, twoLineTitles: true)`.
struct TileTitleText: View {
    let text: String
    var font: Font = AM.Font.tileTitle
    var twoLines = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(
                AM.Layout.tileTitleLineLimit(
                    twoLineTitles: twoLines,
                    accessibilityText: dynamicTypeSize.isAccessibilitySize
                ),
                reservesSpace: twoLines
            )
    }
}
