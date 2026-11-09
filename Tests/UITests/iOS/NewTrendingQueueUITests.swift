import XCTest

/// Songs started from the trending list on New keep playing through that
/// list, as on the website, on the `-UITestMode` fixtures. The fixture
/// trending list is Cure For Me, Be My Star, Young and Beautiful, Send Me an
/// Angel, Wake Me Up Before You Go-Go, Hero.
@MainActor
final class NewTrendingQueueUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// The "Trending Now" card used to queue New Releases, so nothing from the
    /// trending list followed its song.
    func testTrendingCardQueuesTheTrendingList() throws {
        let app = launch()
        let card = element("New.FeatureCard.Trending", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected the Trending Now card.")
        // On iPhone the card starts mostly off screen, where a tap lands on
        // the first card. Scroll the rail until it is fully visible.
        let window = app.windows.firstMatch
        if card.frame.maxX > window.frame.maxX {
            let first = element("New.FeatureCard.NewRelease", in: app)
            first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        }
        let deadline = Date().addingTimeInterval(5)
        while card.frame.maxX > window.frame.maxX + 1, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertLessThanOrEqual(card.frame.maxX, window.frame.maxX + 1, "The Trending Now card never scrolled into view.")
        card.tap()

        assertQueueFollowsTrendingList(in: app)
    }

    /// The preview shows five songs; the sixth must still be queued.
    func testTrendingPreviewRowQueuesTheWholeList() throws {
        let app = launch()
        let row = element("NewSongListPreview.Trending This Week.ui-home-song-3", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Expected the first Trending This Week row.")
        if !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(waitUntilHittable(row), "The first trending row never became tappable.")
        row.tap()

        assertQueueFollowsTrendingList(in: app)
    }

    func testWideHeroTrendingRowQueuesTheTrendingList() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The wide New hero is only shown on iPad."
        )
        let app = launch()
        let hero = element("New.WideHero", in: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 15), "Expected the wide New hero.")
        let row = hero.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Trending Now")).firstMatch
        XCTAssertTrue(waitUntilHittable(row), "Expected the hero's Trending Now row.")
        row.tap()

        assertQueueFollowsTrendingList(in: app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "new"]
        app.launch()
        return app
    }

    /// Opens the queue the way `verifyQueueEditing` does and checks the last
    /// trending song is fifth in Up Next, after Cure For Me.
    private func assertQueueFollowsTrendingList(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mini = element("MiniPlayerBar", in: app)
        XCTAssertTrue(mini.waitForExistence(timeout: 8), "Expected the mini player.", file: file, line: line)
        let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)
        let queueButton = app.buttons["PlayerToolbar.PlayingNext"].firstMatch
        XCTAssertTrue(waitUntilHittable(queueButton), "The queue button never became tappable.", file: file, line: line)
        queueButton.tap()
        XCTAssertTrue(
            element("Queue.List", in: app).waitForExistence(timeout: 8),
            "Expected the queue.",
            file: file,
            line: line
        )

        let first = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "1. Be My Star")).firstMatch
        let last = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "5. Hero")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Expected Be My Star to play next.", file: file, line: line)
        // The list only builds rows near the screen; scroll for the last one.
        let list = element("Queue.List", in: app)
        for _ in 0 ..< 3 where !last.exists {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(last.exists, "Expected the rest of the trending list, ending with Hero, in the queue.", file: file, line: line)
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
