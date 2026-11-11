import XCTest

/// The compact player's artwork morphs into the lyrics header and back. The
/// morph moves the artwork's image, not its frame, so the frame the player
/// reports for the close into the mini player must survive a round trip.
@MainActor
final class PlayerLyricsMorphUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testArtworkStillSettlesAfterLyricsRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home",
                               "-UITestPlayerTracking", "-UITestPlayerClosingArtwork"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
        let song = element("HomeSongSection.Made for You.ui-home-song-1", in: app)
        XCTAssertTrue(song.waitForExistence(timeout: 8), "Expected the first Made for You song.")
        song.tap()
        let mini = app.buttons["MiniPlayerBar"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
        mini.tap()
        let handle = app.buttons["PlayerDismissHandle"]
        XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })

        let showLyrics = app.buttons["Show Lyrics"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 8) { showLyrics.isHittable }, "Expected the lyrics toggle.")
        showLyrics.tap()
        let hideFromHeader = app.buttons["Hide lyrics"].firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 8) { hideFromHeader.isHittable },
            "Expected the lyrics header, which hides lyrics when tapped."
        )
        hideFromHeader.tap()
        XCTAssertTrue(
            waitUntil(timeout: 8) { showLyrics.isHittable && element("PlayerArtwork", in: app).isHittable },
            "Expected the artwork surface back after hiding lyrics."
        )

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)),
                    withVelocity: 700, thenHoldForDuration: 0)
        XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
        mini.tap()
        XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })
        let probe = app.descendants(matching: .any)["PlayerTrackingProbe"].firstMatch
        let measurements = try XCTUnwrap(probe.value as? String).split(separator: ",")
        guard measurements.count == 6 else {
            XCTFail("The landing tracking probe must report six measurements.")
            return
        }
        XCTAssertGreaterThan(Int(measurements[4]) ?? 0, 8,
                             "Closing after a lyrics round trip must still land the artwork in the mini player.")
        XCTAssertGreaterThan(Int(measurements[5]) ?? 0, 1,
                             "The rendered artwork should dip below its resting thumbnail position before settling.")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
