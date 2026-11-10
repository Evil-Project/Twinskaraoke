import XCTest

/// New's first card is the latest karaoke stream's setlist, which the website
/// leads with as "Recent Setlist" and the Setlists screen calls "Latest
/// Stream". It used to read "Updated Playlist / New Tracks" over the newest
/// song. The fixture setlist holds the six fixture songs in reverse.
@MainActor
final class NewLatestStreamUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Tapping the card opens the setlist, like the setlist tiles on New.
    func testLatestStreamCardOpensTheSetlist() throws {
        let app = launch()
        let card = latestStreamCard(in: app)
        card.tap()

        XCTAssertTrue(
            element("PlaylistDetail.Overview", in: app).waitForExistence(timeout: 8),
            "Expected the card to open the setlist."
        )
        XCTAssertFalse(element("MiniPlayerBar", in: app).exists, "Opening the setlist shouldn't start playback.")
    }

    /// The card's play button plays the setlist in order without leaving New.
    func testLatestStreamPlayButtonPlaysTheSetlist() throws {
        let app = launch()
        _ = latestStreamCard(in: app)
        let play = element("New.FeatureCard.LatestStream.Play", in: app)
        XCTAssertTrue(waitUntilHittable(play), "Expected the card's play button.")
        play.tap()
        XCTAssertFalse(element("PlaylistDetail.Overview", in: app).exists, "Playing shouldn't open the setlist.")

        openQueue(in: app)
        let next = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "1. Young and Beautiful")).firstMatch
        let last = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "5. Wake Me Up Before You Go-Go")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Expected the setlist's second song to play next.")
        let list = element("Queue.List", in: app)
        for _ in 0 ..< 3 where !last.exists {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(last.exists, "Expected the rest of the setlist, in setlist order, in the queue.")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "new"]
        app.launch()
        return app
    }

    /// The card, after checking what it says.
    private func latestStreamCard(in app: XCUIApplication) -> XCUIElement {
        let card = element("New.FeatureCard.LatestStream", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected the Latest Stream card.")
        XCTAssertEqual(card.label, "Latest Stream, Neuro Karaoke - November 1, 2026 Setlist")
        XCTAssertEqual(card.value as? String, "6 songs · 21 min")
        XCTAssertTrue(waitUntilHittable(card), "The Latest Stream card never became tappable.")
        return card
    }

    /// Opens the queue the way `verifyQueueEditing` does.
    private func openQueue(in app: XCUIApplication) {
        let mini = element("MiniPlayerBar", in: app)
        XCTAssertTrue(mini.waitForExistence(timeout: 8), "Expected the mini player.")
        let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)
        let queueButton = app.buttons["PlayerToolbar.PlayingNext"].firstMatch
        XCTAssertTrue(waitUntilHittable(queueButton), "The queue button never became tappable.")
        queueButton.tap()
        XCTAssertTrue(element("Queue.List", in: app).waitForExistence(timeout: 8), "Expected the queue.")
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
}
