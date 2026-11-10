import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// A lyric line must take the same room whether or not it is the current
/// one, or the list reflows under its own scroll on every line change.
@MainActor
struct LyricLineLayoutTests {
    private static let width: CGFloat = 340

    private func height(of line: LyricLine, isCurrent: Bool, showTranslation: Bool = false) -> CGFloat {
        let row = LyricLineRow(
            line: line,
            index: 3,
            currentIndex: isCurrent ? 3 : 1,
            currentTime: nil,
            animatesLineChanges: false,
            showTranslation: showTranslation,
            nextLineTime: nil,
            onSeek: { _ in }
        )
        .frame(width: Self.width)
        return UIHostingController(rootView: row)
            .sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
    }

    /// The current line keeps 4pt more padding above and below.
    private static let paddingDifference: CGFloat = 8

    @Test func becomingCurrentDoesNotRewrapALine() {
        let line = LyricLine(time: 12, text: "And play the same songs we've known since that day")
        let current = height(of: line, isCurrent: true)
        let other = height(of: line, isCurrent: false)
        #expect(
            abs(current - other - Self.paddingDifference) < 1,
            "The line is \(current)pt tall when current and \(other)pt otherwise"
        )
    }

    @Test func aTranslatedLineKeepsItsWrappingToo() {
        let line = LyricLine(
            time: 12,
            text: "We're waiting every night to finally roam and invite",
            translatedText: "Wir warten jede Nacht darauf, endlich umherzustreifen und einzuladen"
        )
        let current = height(of: line, isCurrent: true, showTranslation: true)
        let other = height(of: line, isCurrent: false, showTranslation: true)
        // Padding, plus 3pt more between the line and its translation.
        #expect(abs(current - other - Self.paddingDifference - 3) < 1)
    }
}
