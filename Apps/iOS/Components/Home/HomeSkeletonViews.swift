import SwiftUI

struct HomeSkeletonView: View {
    var availableWidth: CGFloat = 390
    /// How many of the leading shelves hold playlists; see
    /// `BrowseLoadingPlaceholder.playlistShelfCount`.
    var playlistShelfCount = 0

    var body: some View {
        BrowseLoadingPlaceholder(
            availableWidth: availableWidth,
            label: String(localized: "Loading Home"),
            playlistShelfCount: playlistShelfCount
        )
    }
}

struct NewSkeletonView: View {
    var availableWidth: CGFloat = 390

    var body: some View {
        BrowseLoadingPlaceholder(availableWidth: availableWidth, label: String(localized: "Loading New"), featured: true)
    }
}

/// Static placeholders establish the browsing layout without running decorative animations.
private struct BrowseLoadingPlaceholder: View {
    let availableWidth: CGFloat
    let label: String
    var featured = false
    /// The leading shelves that stand in for playlist shelves, whose tiles
    /// reserve a second title line.
    var playlistShelfCount = 0
    @ScaledMetric(relativeTo: .subheadline) private var labelAllowance: CGFloat = AM.Layout.shelfLabelAllowance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Sized like the shelves that replace it, at accessibility text sizes
    /// too, so the page does not jump when the content arrives.
    private var tileWidth: CGFloat {
        AM.Layout.shelfTileWidth(
            for: min(availableWidth, AM.Layout.wideContentMaxWidth),
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private func tileHeight(forShelf index: Int) -> CGFloat {
        AM.Layout.mediaShelfHeight(
            tileWidth: tileWidth,
            labelAllowance: labelAllowance,
            accessibilityText: dynamicTypeSize.isAccessibilitySize,
            twoLineTitles: index < playlistShelfCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            if featured {
                VStack(alignment: .leading, spacing: AM.Spacing.s) {
                    MusicSkeletonLine(width: 110, height: 10)
                    MusicSkeletonLine(width: 180, height: 20)
                    MusicSkeletonBlock(cornerRadius: AM.Radius.card)
                        .frame(height: min(max(availableWidth - AM.Spacing.screenMargin * 2, 300), 420) * 0.56)
                }
                .frame(width: min(max(availableWidth - AM.Spacing.screenMargin * 2, 300), 420))
                .padding(.horizontal, AM.Spacing.screenMargin)
                .accessibilityHidden(true)
            }

            ForEach(0..<2) { index in
                VStack(alignment: .leading, spacing: AM.Spacing.sectionHeaderGap) {
                    HStack {
                        MusicSkeletonLine(width: index == 0 ? 140 : 180, height: 22)
                            .accessibilityHidden(true)
                        Spacer()
                        if index == 0 {
                            ProgressView().accessibilityLabel(label)
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)

                    HStack(alignment: .top, spacing: AM.Spacing.l) {
                        ForEach(0..<6) { _ in
                            VStack(alignment: .leading, spacing: AM.Spacing.s) {
                                MusicSkeletonBlock(cornerRadius: AM.Radius.card)
                                    .frame(width: tileWidth, height: tileWidth)
                                MusicSkeletonLine(width: tileWidth * 0.82)
                                MusicSkeletonLine(width: tileWidth * 0.56, height: 11, tone: .tertiary)
                            }
                            .frame(width: tileWidth, height: tileHeight(forShelf: index), alignment: .topLeading)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: AM.Layout.wideContentMaxWidth)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
