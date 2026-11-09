import XCTest

/// The 7-day trending list carries the website's name, "Trending This Week",
/// on Home and New, on the `-UITestMode` fixtures. It used to appear as
/// "More to Explore" on both and again as "Best New Songs" on New.
@MainActor
final class TrendingThisWeekUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomeShowsTrendingThisWeekBelowMadeForYou() throws {
        let app = launch(section: "home")

        let madeForYou = app.staticTexts["Made for You"].firstMatch
        let trending = app.staticTexts["Trending This Week"].firstMatch
        XCTAssertTrue(madeForYou.waitForExistence(timeout: 15), "Expected Home to render Made for You.")
        XCTAssertTrue(trending.waitForExistence(timeout: 8), "Expected Home to render Trending This Week.")
        XCTAssertFalse(app.staticTexts["More to Explore"].exists, "The trending list is no longer called More to Explore.")

        // The wide iPad overview puts trending in its side column, so the
        // order only applies to the single-column layout.
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssertLessThan(
                madeForYou.frame.minY,
                trending.frame.minY,
                "Trending This Week sits below Made for You, as on the website."
            )
            XCTAssertTrue(
                element("HomeSongSection.Trending This Week.ui-home-song-3", in: app).waitForExistence(timeout: 5),
                "Expected the trending fixture songs in the shelf."
            )
        }
    }

    func testNewShowsTrendingThisWeekOnce() throws {
        let app = launch(section: "new")

        let trending = app.staticTexts.matching(NSPredicate(format: "label == %@", "Trending This Week"))
        XCTAssertTrue(trending.firstMatch.waitForExistence(timeout: 15), "Expected New to render Trending This Week.")
        XCTAssertEqual(trending.count, 1, "New shows the trending list once.")
        XCTAssertFalse(app.staticTexts["Best New Songs"].exists, "The trending list is no longer called Best New Songs.")
        XCTAssertFalse(app.staticTexts["More to Explore"].exists, "The trending list is no longer repeated as More to Explore.")
    }

    private func launch(section: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", section]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
