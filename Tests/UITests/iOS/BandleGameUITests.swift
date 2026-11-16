import XCTest

@MainActor
final class BandleGameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNewCardStartsChallengeAndCompletesCorrectGuess() throws {
        let app = launchBandle()
        let play = element("Bandle.PlayToday", in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()

        let field = element("Bandle.GuessField", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hero")
        let answer = element("Bandle.Song.ui-song-hero", in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        submitSelectedGuess(in: app)

        XCTAssertTrue(app.staticTexts["Well done!"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("Bandle.ShareResult", in: app).exists)
        XCTAssertTrue(app.staticTexts["Hero"].exists)
    }

    func testPracticeReplayStaysAvailableAndCompletesLocally() throws {
        let app = launchBandle()
        let practice = element("Bandle.Practice", in: app)
        XCTAssertTrue(practice.waitForExistence(timeout: 10))
        practice.tap()

        let field = element("Bandle.GuessField", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hero")
        let answer = element("Bandle.Song.ui-song-hero", in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        submitSelectedGuess(in: app)

        XCTAssertTrue(app.staticTexts["Well done!"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("Bandle.PlayAgain", in: app).exists)
        XCTAssertTrue(element("Bandle.ShareResult", in: app).exists)
    }

    private func launchBandle() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "new"]
        app.launch()
        let card = element("New.BandleCard", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The keyboard's Search key submits a selected guess, so use it when the
    /// keyboard is up; otherwise tap the Submit button.
    private func submitSelectedGuess(in app: XCUIApplication) {
        let search = app.keyboards.buttons["Search"].firstMatch
        if search.exists {
            search.tap()
            return
        }
        let submit = element("Bandle.SubmitGuess", in: app)
        XCTAssertTrue(waitUntilHittable(submit))
        submit.tap()
    }
}
