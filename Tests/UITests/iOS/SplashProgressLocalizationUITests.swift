import XCTest

extension SplashExperienceUITests {
    @objc func testProgressKeepsGermanLocalizationAfterRebase() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashReset", "-UITestSplashUpdate",
                               "-nk.language", "de", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        defer { app.terminate() }
        let progress = app.staticTexts["Splash.Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        XCTAssertEqual(progress.label, "Willkommen, Folie 1 von 3")
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Update, Folie 1 von 2"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 5), .completed)
        capture("Localized German update progress", in: app)
    }
}
