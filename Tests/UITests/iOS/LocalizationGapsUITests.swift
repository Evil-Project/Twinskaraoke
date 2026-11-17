import XCTest

/// Strings that used to reach the screen in English in every language, or
/// named the wrong visibility.
final class LocalizationGapsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Credit roles were drawn with `Text(String)`, so they never reached the
    /// catalog and stayed English under every app language.
    func testCreditRolesFollowTheAppLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-nk.language", "de"]
        app.launch()
        defer { app.terminate() }

        tapFirst(of: [app.buttons["AccountToolbarButton"], app.otherElements["AccountToolbarButton"]])
        tapFirst(of: [app.buttons["Über"], app.staticTexts["Über"]])
        // The About rows draw their titles verbatim, so the row may still read "Credits".
        let credits = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Mitwirkende", "Credits")
        tapFirst(of: [app.buttons.matching(credits).firstMatch], scrolling: app)

        XCTAssertTrue(app.staticTexts["Hauptentwickler"].waitForExistence(timeout: 8), "Expected the role in German.")
        XCTAssertTrue(app.staticTexts["SillyProotSoda"].exists, "Expected names to stay as written.")
        XCTAssertFalse(app.staticTexts["Main Developer"].exists)
    }

    /// An unnamed public playlist was announced as "New private playlist".
    func testNewPlaylistPreviewNamesItsVisibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-nk.language", "en", "-UITestInitialSection", "library"]
        app.launch()
        defer { app.terminate() }

        let moreActions = app.buttons["More Library Actions"]
        if moreActions.waitForExistence(timeout: 8) {
            moreActions.tap()
        }
        tapFirst(of: [app.buttons["New Playlist"]])

        let privatePreview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "New private playlist")).firstMatch
        XCTAssertTrue(privatePreview.waitForExistence(timeout: 8), "Expected the private preview first.")

        let visibility = app.switches.firstMatch
        XCTAssertTrue(visibility.waitForExistence(timeout: 5))
        visibility.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        let publicPreview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "New public playlist")).firstMatch
        XCTAssertTrue(publicPreview.waitForExistence(timeout: 5), "Expected the preview to name the public visibility.")
    }

    /// Taps the first candidate that becomes hittable, scrolling `scrolling`
    /// up between attempts when it is given.
    private func tapFirst(
        of candidates: [XCUIElement],
        scrolling: XCUIApplication? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(scrolling == nil ? 8 : 20)
        repeat {
            if let element = candidates.first(where: { $0.exists && $0.isHittable }) {
                element.tap()
                return
            }
            if let scrolling {
                scrolling.swipeUp()
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        } while Date() < deadline
        XCTFail("None of \(candidates) appeared.", file: file, line: line)
    }
}
