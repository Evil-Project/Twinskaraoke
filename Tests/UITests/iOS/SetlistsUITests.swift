import XCTest

/// Karaoke Setlists, on the `-UITestMode` fixtures: the latest stream leads
/// the list, the year menu filters it, and a setlist opens its songs.
@MainActor
final class SetlistsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLibraryOpensSetlistsFilteredByYear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "library"]
        app.launch()

        let link = app.buttons["Karaoke Setlists"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Expected the Karaoke Setlists link in Library.")
        link.tap()

        let latest = element("Setlists.latest", in: app)
        let halloween = element("Setlists.row.ui-setlist-halloween", in: app)
        let christmas = element("Setlists.row.ui-setlist-christmas", in: app)
        XCTAssertTrue(latest.waitForExistence(timeout: 8), "Expected the latest stream's setlist first.")
        XCTAssertTrue(halloween.waitForExistence(timeout: 8), "Expected the 2026 setlists.")
        XCTAssertTrue(christmas.exists, "Expected the 2025 setlist.")

        let yearMenu = app.buttons["Setlists.yearMenu"].firstMatch
        XCTAssertTrue(yearMenu.waitForExistence(timeout: 5), "Expected the year menu in the toolbar.")
        yearMenu.tap()
        let year2025 = app.buttons["2025"].firstMatch
        XCTAssertTrue(year2025.waitForExistence(timeout: 5), "Expected 2025 in the year menu.")
        year2025.tap()

        // Choosing a year empties the list until that year's page arrives, so
        // wait for the final state rather than for Halloween to go.
        XCTAssertTrue(
            waitUntil(timeout: 8) { christmas.exists && !halloween.exists },
            "Expected only the 2025 setlist once the year is chosen."
        )
        XCTAssertFalse(latest.exists, "The latest stream leads the unfiltered list only.")

        christmas.tap()
        let title = "Neuro Christmas Karaoke - December 25, 2025 Setlist"
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 8)
                || app.staticTexts[title].waitForExistence(timeout: 8),
            "Expected the setlist to open its playlist screen."
        )
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
