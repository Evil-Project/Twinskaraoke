import XCTest

extension SplashExperienceUITests {
    @objc func testWebsiteCallbackAdvancesOfflineDeveloperWalkthrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashWebsites", "-UITestSplashReset",
                               "-UITestSplashResetControls", "-UITestSplashDeveloperControls"]
        app.launch()
        waitForProgress("Welcome, slide 1 of 3", in: app)
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        waitForProgress("Update, slide 1 of 4", in: app)
        app.buttons["Splash.Next"].tap()
        completeOfflineForms(in: app)
        waitForProgress("Update, slide 4 of 4", in: app)
        app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
        openDeveloper(app)
        tap("Developer.SplashTesting", app: app); tap("Update", app: app)
        XCUIDevice.shared.press(.home); app.activate()
        waitForProgress("Update, slide 1 of 4", in: app)
        XCTAssertTrue(app.staticTexts["Example release notes"].exists)
        let toggle = app.buttons["Splash.Changelog.Toggle"]
        XCTAssertEqual(toggle.label, "Show full changelog")
        capture("Condensed changelog", in: app)
        toggle.tap(); XCTAssertEqual(toggle.label, "Show less")
        capture("Expanded changelog", in: app)
        app.buttons["Splash.Next"].tap()
        completeOfflineForms(in: app)
        waitForProgress("Update, slide 4 of 4", in: app)
        app.buttons["Splash.Back"].tap()
        waitForProgress("Update, slide 3 of 4", in: app)
        XCTAssertTrue(app.staticTexts["Website step complete."].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
    }

    private func completeOfflineForms(in app: XCUIApplication) {
        let field = app.webViews.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap(); field.typeText("First form")
        let complete = app.webViews.buttons["Complete test page"]
        XCTAssertTrue(complete.waitForExistence(timeout: 15)); complete.tap()
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let input = object as? XCUIElement, input.exists else { return false }
            return input.value as? String != "First form"
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 15), .completed)
        XCTAssertTrue(complete.waitForExistence(timeout: 15)); complete.tap()
    }
}
