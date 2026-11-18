import XCTest

extension SplashExperienceUITests {
    @objc func testWebsiteTapCollapsesRecoveryWithoutResizingOrZooming() async throws {
        let app = launchStudio()
        tap("Walkthrough", app: app); tap("Update", app: app)
        tap("SplashStudio.Preview", app: app)
        app.buttons["Splash.Next"].tap()
        let web = app.webViews.firstMatch
        let title = web.staticTexts["Website test"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["Splash.Web.Loading"].firstMatch.waitForNonExistence(timeout: 8))
        let recovery = app.buttons["Splash.Web.Recovery"]
        let expandedWidth = recovery.frame.width
        recovery.tap()
        tap("Keep filling out", app: app)
        XCTAssertEqual(recovery.frame.width, expandedWidth, accuracy: 1)
        title.tap()
        for _ in 0..<100 {
            if recovery.frame.width <= recovery.frame.height * 1.5 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertLessThanOrEqual(recovery.frame.width, recovery.frame.height * 1.5)
        // iPad can change the top status-bar inset. Verify bottom coverage, not raw height.
        XCTAssertGreaterThanOrEqual(web.frame.maxY, app.frame.maxY - 44,
                                    "Only the system home-indicator safe area may remain below the website.")
        XCTAssertTrue(web.frame.contains(recovery.frame), "Recovery must float over the website, not reserve a footer.")
        XCTAssertGreaterThan(recovery.frame.midX, app.frame.midX)
        let titleHeight = title.frame.height
        web.pinch(withScale: 2, velocity: 1)
        XCTAssertEqual(title.frame.height, titleHeight, accuracy: 1)
        capture("Compact website recovery bubble", in: app)
        recovery.tap()
        tap("Keep filling out", app: app)
        recovery.tap()
        tap("Continue for now", app: app)
        waitForProgress("Update, slide 3 of 3", in: app)
    }
}
