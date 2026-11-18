import XCTest

extension SplashExperienceUITests {
    @objc func testStandaloneReleaseNotesExpandCollapseAndComplete() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashReset",
                               "-UITestSplashResetControls", "-UITestSplashDeveloperControls", "-UITestSplashChangelogOnly"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        finishVisibleWalkthroughs(app)
        XCTAssertFalse(app.staticTexts["Splash.Progress"].exists)
        openDeveloper(app)
        tap("Developer.SplashTesting", app: app)
        tap("Update", app: app)
        XCUIDevice.shared.press(.home)
        app.activate()

        waitForProgress("Update, slide 1 of 1", in: app)
        let toggle = app.buttons["Splash.Changelog.Toggle"]
        XCTAssertEqual(app.buttons.matching(identifier: "Splash.Changelog.Toggle").count, 1)
        XCTAssertEqual(toggle.label, "Show full changelog")
        XCTAssertTrue(app.staticTexts["Play saved songs offline."].exists)
        XCTAssertFalse(app.staticTexts["Start a downloaded song on Apple Watch."].exists)
        recordReleaseNotes("Condensed release notes", in: app)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show less")
        XCTAssertEqual(app.buttons.matching(identifier: "Splash.Changelog.Toggle").count, 1)
        XCTAssertTrue(app.staticTexts["Start a downloaded song on Apple Watch."].exists)
        XCTAssertGreaterThanOrEqual(toggle.frame.minY, app.staticTexts["See the song reveal after the round."].frame.maxY)
        XCTAssertLessThanOrEqual(toggle.frame.maxY, app.buttons["Splash.Complete"].frame.minY)
        recordReleaseNotes("Expanded release notes", in: app)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show full changelog")
        XCTAssertFalse(app.staticTexts["Start a downloaded song on Apple Watch."].exists)
        app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
    }

    private func recordReleaseNotes(_ name: String, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
