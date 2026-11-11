import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// Shelves and their tiles at an accessibility text size.
@MainActor
struct AccessibilityShelfLayoutTests {
    private func height(of view: some View, width: CGFloat, at size: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    @Test func aPhoneShelfShowsOneWideTileAtAnAccessibilitySize() {
        let standard = AM.Layout.shelfTileWidth(for: 402)
        #expect(AM.Layout.shelfTileWidth(for: 402, accessibilityText: false) == standard)
        let large = AM.Layout.shelfTileWidth(for: 402, accessibilityText: true)
        #expect(large > standard * 1.5)
        // The next tile still shows, so the shelf reads as scrollable.
        #expect(AM.Spacing.screenMargin + large + AM.Spacing.l < 402 - 24)
    }

    @Test func aWideShelfKeepsItsTilesAtAnAccessibilitySize() {
        #expect(AM.Layout.shelfTileWidth(for: 1_000, accessibilityText: true) == AM.Layout.shelfTileWidth(for: 1_000))
    }

    @Test func theShelfMakesRoomForASecondTitleLine() {
        let standard = AM.Layout.mediaShelfHeight(tileWidth: 160, labelAllowance: 90)
        #expect(AM.Layout.mediaShelfHeight(tileWidth: 160, labelAllowance: 90, accessibilityText: false) == standard)
        #expect(AM.Layout.mediaShelfHeight(tileWidth: 160, labelAllowance: 90, accessibilityText: true) == standard + 34)
    }

    @Test func aPlaylistShelfMakesRoomForASecondTitleLine() {
        let standard = AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: 90, accessibilityText: false, twoLineTitles: true
        )
        let accessibility = AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: 90, accessibilityText: true, twoLineTitles: true
        )
        #expect(abs(standard - 270) < 0.001, "Got \(standard)")
        #expect(abs(accessibility - 284) < 0.001, "Got \(accessibility)")
    }

    @Test func aSongShelfKeepsOneTitleLine() {
        let standard = AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: 90, accessibilityText: false, twoLineTitles: false
        )
        let accessibility = AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: 90, accessibilityText: true, twoLineTitles: false
        )
        #expect(abs(standard - 250) < 0.001, "Got \(standard)")
        #expect(abs(accessibility - 284) < 0.001, "Got \(accessibility)")
    }

    @Test func tileTitleLineLimitByKindAndSize() {
        #expect(AM.Layout.tileTitleLineLimit(twoLineTitles: true, accessibilityText: false) == 2)
        #expect(AM.Layout.tileTitleLineLimit(twoLineTitles: false, accessibilityText: false) == 1)
        #expect(AM.Layout.tileTitleLineLimit(twoLineTitles: false, accessibilityText: true) == 2)
        #expect(AM.Layout.tileTitleLineLimit(twoLineTitles: true, accessibilityText: true) == 2)
    }

    /// The label allowance a shelf scales with `@ScaledMetric(relativeTo: .subheadline)`.
    private func labelAllowance(at size: DynamicTypeSize) -> CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(
            for: AM.Layout.shelfLabelAllowance,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        )
    }

    private func playlistTile(_ name: String, width: CGFloat) -> some View {
        PlaylistGridCell(
            playlist: Playlist(id: name, name: name, songCount: 3, mosaicMedia: nil, songListDTOs: nil),
            width: width
        )
    }

    private func songTile(_ title: String, width: CGFloat) -> some View {
        MusicGridCard(
            song: UITestFixtures.song(id: title, title: title, artist: "Artist"),
            context: [],
            width: width
        )
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .xxxLarge])
    func aPlaylistTileTakesTwoTitleLinesWithinItsShelf(size: DynamicTypeSize) {
        let delta = height(of: playlistTile("Evil", width: 160), width: 160, at: size)
            - height(of: songTile("Riot", width: 160), width: 160, at: size)
        let allowance = labelAllowance(at: size)
        let room = AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: allowance, accessibilityText: false, twoLineTitles: true
        ) - AM.Layout.mediaShelfHeight(
            tileWidth: 160, labelAllowance: allowance, accessibilityText: false, twoLineTitles: false
        )
        #expect(delta > 12, "Expected a reserved second title line at \(size): \(delta)")
        #expect(delta <= room + 1, "The second line takes \(delta) at \(size); the shelf adds \(room)")
    }

    @Test func aPlaylistTileReservesTwoTitleLinesAtEverySize() {
        for (size, width) in [(DynamicTypeSize.large, CGFloat(160)), (.accessibility5, 270)] {
            let short = height(of: playlistTile("Evil", width: width), width: width, at: size)
            let long = height(of: playlistTile("Evil Halloween Karaoke - October 29", width: width), width: width, at: size)
            #expect(long == short, "Expected the same height at \(size): \(long) against \(short)")
        }
        let playlist = height(of: playlistTile("Evil", width: 270), width: 270, at: .accessibility5)
        let song = height(of: songTile("Riot", width: 270), width: 270, at: .accessibility5)
        #expect(playlist > song + 20, "Expected a reserved second title line: \(playlist) against \(song)")
    }

    @Test func aSongTileTitleWrapsAtAnAccessibilitySize() {
        func tile(_ title: String) -> some View {
            MusicGridCard(
                song: UITestFixtures.song(id: title, title: title, artist: "Artist"),
                context: [],
                width: 270
            )
        }
        let short = height(of: tile("Riot"), width: 270, at: .accessibility5)
        let long = height(of: tile("Five Nights at Freddy's"), width: 270, at: .accessibility5)
        #expect(long > short + 20, "Expected a second title line: \(long) against \(short)")
    }

    @Test func aSongTileTitleStaysOneLineAtAStandardSize() {
        let short = height(of: songTile("Riot", width: 160), width: 160, at: .large)
        let long = height(of: songTile("Five Nights at Freddy's - Neuro Karaoke Version", width: 160), width: 160, at: .large)
        #expect(long == short, "Expected one title line: \(long) against \(short)")
    }

    @Test func theHomePlaceholderGrowsLikeItsPlaylistShelves() {
        let width: CGFloat = 390
        let two = height(of: HomeSkeletonView(availableWidth: width, playlistShelfCount: 2), width: width, at: .large)
        let none = height(of: HomeSkeletonView(availableWidth: width, playlistShelfCount: 0), width: width, at: .large)
        let tileWidth = AM.Layout.shelfTileWidth(for: width, accessibilityText: false)
        let allowance = labelAllowance(at: .large)
        let step = AM.Layout.mediaShelfHeight(
            tileWidth: tileWidth, labelAllowance: allowance, accessibilityText: false, twoLineTitles: true
        ) - AM.Layout.mediaShelfHeight(
            tileWidth: tileWidth, labelAllowance: allowance, accessibilityText: false, twoLineTitles: false
        )
        #expect(abs((two - none) - 2 * step) < 0.01, "Grew by \(two - none); two shelves add \(2 * step)")
    }
}
