import XCTest

/// The notice Home and New show over the copy saved on the device, driven by
/// `-UITestHomeSavedContent` on the `-UITestMode` fixtures.
@MainActor
final class HomeSavedContentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomeAndNewShowTheSavedContentNotice() throws {
        let app = launch(section: "home", savedContent: true)
        let notice = element("home.savedContentNotice", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "Expected the saved-content notice on Home.")
        XCTAssertTrue(notice.label.contains("Couldn't Refresh"), "Expected the notice's title in its label, got \(notice.label).")

        let newTab = app.tabBars.buttons["New"].firstMatch
        XCTAssertTrue(newTab.waitForExistence(timeout: 5), "Expected the New tab.")
        newTab.tap()
        XCTAssertTrue(
            app.navigationBars["New"].waitForExistence(timeout: 8),
            "Expected New to open."
        )
        XCTAssertTrue(
            element("home.savedContentNotice", in: app).waitForExistence(timeout: 8),
            "Expected the saved-content notice on New."
        )
    }

    func testNoNoticeWithoutSavedContent() throws {
        let app = launch(section: "home", savedContent: false)
        XCTAssertTrue(
            element("Home.RecentlyPlayed", in: app).waitForExistence(timeout: 15)
                || app.staticTexts["Made for You"].waitForExistence(timeout: 15),
            "Expected Home's shelves."
        )
        XCTAssertFalse(element("home.savedContentNotice", in: app).exists, "No notice when the shelves are fresh.")

        app.tabBars.buttons["New"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New"].waitForExistence(timeout: 8), "Expected New to open.")
        XCTAssertTrue(app.staticTexts["New Releases"].waitForExistence(timeout: 8), "Expected New's shelves.")
        XCTAssertFalse(element("home.savedContentNotice", in: app).exists, "No notice on New either.")
    }

    private func launch(section: String, savedContent: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", section]
            + (savedContent ? ["-UITestHomeSavedContent"] : [])
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
