import SwiftUI

/// Shelf sizing at an accessibility text size.
///
/// A shelf's height is fixed and its tiles are sized from the screen width, so
/// neither follows the text by itself: at the largest size a phone showed two
/// and a bit tiles whose labels had room for about five letters, on one line.
extension AM.Layout {
    /// One more tile-title line and half of a second header line, as a share
    /// of `shelfLabelAllowance`: 34 of its 90 points. Headers wrap there too.
    /// It already covers the second line `tileTitleSecondLineShare` adds at
    /// a standard size, so the two are never added together.
    static let tileTitleLineShare: CGFloat = 34.0 / 90.0

    /// One more subheadline line, as a share of `shelfLabelAllowance`: 20 of
    /// its 90 points. Playlist tiles keep room for a second title line at a
    /// standard size, where setlist names would otherwise lose their date.
    static let tileTitleSecondLineShare: CGFloat = 20.0 / 90.0

    /// The title lines a tile shows: two for a playlist, and two for any tile
    /// at an accessibility text size.
    static func tileTitleLineLimit(twoLineTitles: Bool, accessibilityText: Bool) -> Int {
        twoLineTitles || accessibilityText ? 2 : 1
    }

    /// The tile width, with one tile and the edge of the next on a phone at
    /// an accessibility text size. Wide layouts already give a tile room.
    static func shelfTileWidth(
        for availableWidth: CGFloat,
        compact: Bool = false,
        accessibilityText: Bool
    ) -> CGFloat {
        guard accessibilityText, availableWidth < 700 else {
            return shelfTileWidth(for: availableWidth, compact: compact)
        }
        let visibleItems: CGFloat = 1.35
        let rawWidth = (availableWidth - AM.Spacing.screenMargin * 2 - AM.Spacing.l * (visibleItems - 1)) / visibleItems
        return min(max(rawWidth, compact ? 152 : 190), 300)
    }

    /// The shelf height, with room for the second title line `TileTitleText`
    /// takes at an accessibility text size, and at every size when the shelf
    /// holds `twoLineTitles` tiles.
    static func mediaShelfHeight(
        tileWidth: CGFloat,
        labelAllowance: CGFloat,
        accessibilityText: Bool,
        twoLineTitles: Bool = false
    ) -> CGFloat {
        let share: CGFloat = if accessibilityText {
            1 + tileTitleLineShare
        } else if twoLineTitles {
            1 + tileTitleSecondLineShare
        } else {
            1
        }
        return tileWidth + labelAllowance * share
    }
}
