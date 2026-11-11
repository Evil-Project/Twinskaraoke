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

    @Test func aPlaylistTileTitleWrapsAtAnAccessibilitySize() {
        func tile(_ name: String) -> some View {
            PlaylistGridCell(
                playlist: Playlist(id: name, name: name, songCount: 3, mosaicMedia: nil, songListDTOs: nil),
                width: 270
            )
        }
        let short = height(of: tile("Evil"), width: 270, at: .accessibility5)
        let long = height(of: tile("Evil Halloween Karaoke"), width: 270, at: .accessibility5)
        #expect(long > short + 20, "Expected a second title line: \(long) against \(short)")
        #expect(height(of: tile("Evil Halloween Karaoke - October 29"), width: 160, at: .large)
            == height(of: tile("Evil"), width: 160, at: .large))
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
}
