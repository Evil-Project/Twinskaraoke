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
