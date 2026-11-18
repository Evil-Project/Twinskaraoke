import XCTest

extension SplashExperienceUITests {
    @objc func testWebsiteRecoveryStaysFixedDuringWebGestures() {
        let app = launchWebsiteWalkthrough()
        app.buttons["Splash.Next"].tap()
        let web = app.webViews.firstMatch
        let title = web.staticTexts["Website test"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["Splash.Web.Loading"].firstMatch.waitForNonExistence(timeout: 8))
        let recovery = app.buttons["Splash.Web.Recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
        let initialFrame = web.frame
        let recoveryFrame = recovery.frame
        recovery.tap()
        tap("Keep filling out", app: app)
        title.tap()
        XCTAssertEqual(web.frame, initialFrame)
        XCTAssertEqual(recovery.frame, recoveryFrame)
        // iPad can change the top status-bar inset. Verify bottom coverage, not raw height.
        XCTAssertGreaterThanOrEqual(web.frame.maxY, app.frame.maxY - 44,
                                    "Only the system home-indicator safe area may remain below the website.")
        XCTAssertTrue(web.frame.contains(recovery.frame), "Recovery must float over the website, not reserve a footer.")
        XCTAssertGreaterThan(recovery.frame.midX, app.frame.midX)
        capture("Website recovery bubble", in: app)
        web.pinch(withScale: 2, velocity: 1)
        XCTAssertEqual(web.frame, initialFrame)
        XCTAssertEqual(recovery.frame, recoveryFrame)
        recovery.tap()
        tap("Keep filling out", app: app)
        recovery.tap()
        tap("Continue for now", app: app)
        waitForProgress("Update, slide 3 of 3", in: app)
    }
}
