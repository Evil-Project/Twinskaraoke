import SwiftUI

/// Shelf sizing at an accessibility text size.
///
/// A shelf's height is fixed and its tiles are sized from the screen width, so
/// neither follows the text by itself: at the largest size a phone showed two
/// and a bit tiles whose labels had room for about five letters, on one line.
extension AM.Layout {
    /// One more tile-title line and half of a second header line, as a share
    /// of `shelfLabelAllowance`: 34 of its 90 points. Headers wrap there too.
    static let tileTitleLineShare: CGFloat = 34.0 / 90.0

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
    /// takes at an accessibility text size.
    static func mediaShelfHeight(
        tileWidth: CGFloat,
        labelAllowance: CGFloat,
        accessibilityText: Bool
    ) -> CGFloat {
        tileWidth + labelAllowance * (accessibilityText ? 1 + tileTitleLineShare : 1)
    }
}
