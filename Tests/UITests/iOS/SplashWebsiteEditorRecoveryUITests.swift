import XCTest

extension SplashExperienceUITests {
    @objc func testWebsiteFieldsRemainEditableWithoutLosingURL() {
        let app = launchStudio()
        tap("Walkthrough", app: app); tap("Update", app: app); tap("Website", app: app)
        let address = "https://splash-fixture.invalid/form"
        let url = app.textFields["Website URL"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap(); url.typeText(address + "\n")
        tap("Standard slide settings", app: app)
        let symbol = app.textFields["SF Symbol (optional)"]
        reveal(symbol, app: app)
        XCTAssertTrue(symbol.isHittable)
        symbol.tap(); symbol.typeText("notasymbol")
        XCTAssertEqual(symbol.value as? String, "notasymbol")
        symbol.doubleTap(); symbol.typeText(XCUIKeyboardKey.delete.rawValue + "\n")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("Website", app: app)
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertEqual(url.value as? String, address)
        capture("Website settings preserve URL during repair", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("Save Local Draft", app: app)
        XCTAssertTrue(app.staticTexts["Draft saved locally."].waitForExistence(timeout: 5))
    }
}
