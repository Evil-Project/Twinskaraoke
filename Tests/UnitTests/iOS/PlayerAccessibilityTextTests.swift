import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// The player at an accessibility text size: fixed-size controls keep their
/// glyphs inside their targets, and an empty state too tall for its area
/// scrolls instead of pushing its neighbours out.
@MainActor
struct PlayerAccessibilityTextTests {
    private func size(
        of view: some View,
        in proposal: CGSize,
        at size: DynamicTypeSize
    ) -> CGSize {
        UIHostingController(rootView: view.environment(\.dynamicTypeSize, size)).sizeThatFits(in: proposal)
    }

    private static let unbounded = CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)

    @Test func controlGlyphsStopGrowingAtTheLargestStandardSize() {
        let glyph = Image(systemName: "star").font(.title2)
        let largestStandard = size(of: glyph, in: Self.unbounded, at: .xxxLarge)
        #expect(size(of: glyph, in: Self.unbounded, at: .accessibility5).height > largestStandard.height)

        let capped = glyph.playerControlGlyphScaling()
        #expect(size(of: capped, in: Self.unbounded, at: .accessibility5) == largestStandard)
        #expect(size(of: capped, in: Self.unbounded, at: .large) == size(of: glyph, in: Self.unbounded, at: .large))
    }

    @Test func anEmptyStateTooTallForItsAreaScrollsInsideIt() {
        let state = MusicEmptyState(
            title: "No songs queued",
            message: "Songs you play next will appear here."
        )
        let area = CGSize(width: 390, height: 300)
        #expect(size(of: state, in: area, at: .accessibility5).height > area.height)
        #expect(size(of: state.scrollsWhenTooTall(), in: area, at: .accessibility5).height <= area.height)
    }

    @Test func anEmptyStateThatFitsIsLeftAsItIs() {
        let state = MusicEmptyState(
            title: "No songs queued",
            message: "Songs you play next will appear here."
        )
        let area = CGSize(width: 390, height: 600)
        #expect(size(of: state.scrollsWhenTooTall(), in: area, at: .large) == size(of: state, in: area, at: .large))
    }
}
