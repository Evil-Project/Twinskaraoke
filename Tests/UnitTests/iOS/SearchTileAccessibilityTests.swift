import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// The Search browse tiles have fixed heights holding headline text. At an
/// accessibility text size the titles grew past them and were clipped.
@MainActor
struct SearchTileAccessibilityTests {
    /// About a phone tile in the two-column grid, and an iPad one.
    private static let widths: [UserInterfaceSizeClass: CGFloat] = [.compact: 177, .regular: 240]

    private func size(
        of view: some View,
        width: CGFloat,
        sizeClass: UserInterfaceSizeClass,
        at size: DynamicTypeSize
    ) -> CGSize {
        let root = view
            .frame(width: width)
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, size)
        return UIHostingController(rootView: root)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// The height two lines of the title need at full size, as the tile sets them.
    private func titleHeight(_ title: String, width: CGFloat, at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        size(
            of: Text(verbatim: title).font(.headline.bold()).lineLimit(2, reservesSpace: true),
            width: width,
            sizeClass: .compact,
            at: dynamicTypeSize
        ).height
    }

    private func subtitleHeight(_ subtitle: String, width: CGFloat, at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        size(
            of: Text(verbatim: subtitle).font(.subheadline.weight(.semibold)).lineLimit(1),
            width: width,
            sizeClass: .compact,
            at: dynamicTypeSize
        ).height
    }

    @Test(arguments: [UserInterfaceSizeClass.compact, .regular])
    func aGenreTileHoldsTwoTitleLinesAtTheLargestSize(_ sizeClass: UserInterfaceSizeClass) throws {
        let width = try #require(Self.widths[sizeClass])
        let tile = CategoryTile(title: "Electronic Dance Music", gradient: [.blue, .purple])
        let tileHeight = size(of: tile, width: width, sizeClass: sizeClass, at: .accessibility5).height
        let needed = titleHeight("Electronic Dance Music", width: width - 2 * AM.Spacing.m, at: .accessibility5)
            + 2 * AM.Spacing.m
        #expect(tileHeight >= needed, "Tile \(tileHeight)pt, title needs \(needed)pt")
    }

    @Test(arguments: [UserInterfaceSizeClass.compact, .regular])
    func aFeaturedTileHoldsItsTitleAndSubtitleAtTheLargestSize(_ sizeClass: UserInterfaceSizeClass) throws {
        let width = try #require(Self.widths[sizeClass])
        let tile = SearchFeaturedShortcutTile(
            title: "Public Playlists", subtitle: "Community mixes", gradient: [.blue, .purple]
        )
        let tileHeight = size(of: tile, width: width, sizeClass: sizeClass, at: .accessibility5).height
        let textWidth = width - 2 * AM.Spacing.l
        let needed = titleHeight("Public Playlists", width: textWidth, at: .accessibility5) + 5
            + subtitleHeight("Community mixes", width: textWidth, at: .accessibility5)
            + 2 * AM.Spacing.l
        #expect(tileHeight >= needed, "Tile \(tileHeight)pt, text needs \(needed)pt")
    }

    @Test func theTilesKeepTheirHeightsAtTheDefaultSize() {
        let genre = CategoryTile(title: "Pop", gradient: [.blue, .purple])
        let featured = SearchFeaturedShortcutTile(title: "Twinskaraoke Top 100", gradient: [.blue, .purple])
        #expect(size(of: genre, width: 177, sizeClass: .compact, at: .large).height == 92)
        #expect(size(of: genre, width: 240, sizeClass: .regular, at: .large).height == 102)
        #expect(size(of: featured, width: 177, sizeClass: .compact, at: .large).height == 124)
        #expect(size(of: featured, width: 240, sizeClass: .regular, at: .large).height == 144)
    }
}
