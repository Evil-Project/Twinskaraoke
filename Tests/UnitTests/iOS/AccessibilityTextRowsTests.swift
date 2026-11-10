import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// Rows at the largest accessibility text size, measured rather than drawn:
/// a title that wraps makes its row taller, one that truncates does not.
@MainActor
struct AccessibilityTextRowsTests {
    private static let rowWidth: CGFloat = 370

    private func height(of view: some View, at size: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(
            rootView: view
                .frame(width: Self.rowWidth)
                .environment(\.dynamicTypeSize, size)
        )
        return host.sizeThatFits(in: CGSize(width: Self.rowWidth, height: .greatestFiniteMagnitude)).height
    }

    private func songRow(title: String) -> some View {
        SongRow(song: UITestFixtures.song(id: "row-\(title)", title: title, artist: "Artist"), size: .regular)
    }

    @Test func aSongTitleWrapsAtAnAccessibilitySize() {
        let short = height(of: songRow(title: "Riot"), at: .accessibility5)
        let long = height(of: songRow(title: "Five Nights at Freddy's"), at: .accessibility5)
        #expect(long > short + 20, "Expected a second title line: \(long) against \(short)")
    }

    @Test func aSongTitleStaysOnOneLineAtTheDefaultSize() {
        let short = height(of: songRow(title: "Riot"), at: .large)
        let long = height(of: songRow(title: "Five Nights at Freddy's, the Whole Extended Edition"), at: .large)
        #expect(long == short)
    }

    @Test func theDurationGivesWayToTheTitleAtAnAccessibilitySize() {
        #expect(SongRowStatusAccessory.showsDuration("3:27", isAccessibilitySize: false))
        #expect(!SongRowStatusAccessory.showsDuration("3:27", isAccessibilitySize: true))
        #expect(!SongRowStatusAccessory.showsDuration("", isAccessibilitySize: false))
    }

    /// Hidden for room, not from VoiceOver.
    @Test func aHiddenDurationIsStillSpoken() {
        func isSpoken(_ status: SongDownloadStatus, _ duration: String = "3:27", large: Bool = true) -> Bool {
            SongRowSpokenDuration.isNeeded(status: status, durationText: duration, isAccessibilitySize: large)
        }
        let plain = SongDownloadStatus(isDownloaded: false, isDownloading: false)
        #expect(isSpoken(plain))
        // Shown as text at the standard sizes, so nothing extra is needed.
        #expect(!isSpoken(plain, large: false))
        #expect(!isSpoken(plain, ""))
        // The status glyph's own label carries the time.
        #expect(!isSpoken(SongDownloadStatus(isDownloaded: true, isDownloading: false)))
        #expect(!isSpoken(SongDownloadStatus(isDownloaded: false, isDownloading: true)))
    }

    @Test func aLibraryRowTitleWrapsAtAnAccessibilitySize() {
        func row(_ title: String) -> some View {
            LibraryRow(icon: "list.bullet.rectangle", color: .appAccent, title: title)
        }
        let short = height(of: row("Songs"), at: .accessibility5)
        let long = height(of: row("Karaoke Setlists"), at: .accessibility5)
        #expect(long > short + 20, "Expected a second title line: \(long) against \(short)")
        #expect(height(of: row("Karaoke Setlists"), at: .large) == height(of: row("Songs"), at: .large))
    }

    @Test func playAndShuffleStackAtAnAccessibilitySize() {
        let play = LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
        let shuffle = LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
        let pair = LibraryActionButtonRow {
            play
            shuffle
        }
        let single = height(of: play, at: .accessibility5)
        #expect(height(of: pair, at: .accessibility5) > single * 1.8)
        #expect(height(of: pair, at: .large) == height(of: play, at: .large))
    }
}
