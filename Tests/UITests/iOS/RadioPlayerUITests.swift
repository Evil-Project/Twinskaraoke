import XCTest

/// The full-screen player in radio mode, opened from the Radio screen's live
/// station card under the `-UITestMode` fixtures.
@MainActor
final class RadioPlayerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// The radio title row wears the music player's actions in the music
    /// player's order: the favourite star first, then "More".
    func testRadioTitleRowMatchesTheMusicPlayerOrder() throws {
        let app = launchIntoRadioPlayer()

        let favorite = app.buttons["Add to Favorites"].firstMatch
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 8), "Expected the radio player's favourite button.")
        XCTAssertTrue(more.waitForExistence(timeout: 8), "Expected the radio player's More menu.")

        XCTAssertLessThanOrEqual(
            favorite.frame.maxX, more.frame.minX + 1,
            "The favourite star must sit before More, as in the music player."
        )
        XCTAssertEqual(favorite.frame.midY, more.frame.midY, accuracy: 2,
                       "The two title actions must share one row.")
    }

    /// At the largest accessibility text size the radio player used to keep
    /// its full-size artwork, which pushed the toolbar off the bottom of the
    /// screen and squeezed "LIVE RADIO · 24 listening" down to "LIV… · 24…".
    func testRadioPlayerFitsTheScreenAtAccessibilitySizes() throws {
        let app = launchIntoRadioPlayer(arguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let screen = app.windows.firstMatch.frame

        let schedule = app.buttons["PlayerToolbar.PlayingNext"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 8), "Expected the radio player's toolbar.")
        XCTAssertLessThanOrEqual(schedule.frame.maxY, screen.maxY,
                                 "The toolbar must stay on screen at an accessibility text size.")
        XCTAssertTrue(schedule.isHittable)
        for label in ["Add to Favorites", "More"] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.exists, "Expected \(label) in the title row.")
            XCTAssertLessThanOrEqual(button.frame.maxX, screen.maxX, "\(label) was pushed off screen.")
        }
    }

    // MARK: - Helpers

    private func launchIntoRadioPlayer(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "radio"] + arguments
        app.launch()

        let play = app.buttons["Play live station"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { play.isHittable }, "Expected the live station's play button.")
        play.tap()
        let mini = app.buttons["MiniPlayerBar"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable }, "Expected the mini player for the live station.")
        mini.tap()
        let handle = app.buttons["PlayerDismissHandle"]
        XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable }, "Expected the full-screen player.")
        return app
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
