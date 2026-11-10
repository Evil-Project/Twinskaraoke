import XCTest

/// The New tab's featured cards say what they play, on the `-UITestMode`
/// fixtures.
@MainActor
final class NewFeaturedRailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// The second card plays the top trending song ("Cure For Me" in the
    /// fixtures). It used to be labelled "Featured Release", and VoiceOver
    /// read only the song title.
    func testTrendingCardIsLabelledTrendingNow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "new"]
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "New.FeatureCard.Trending").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected the featured card for the top trending song.")
        XCTAssertEqual(card.label, "Trending Now, Cure For Me")
    }

    /// The second card peeks in at the trailing edge, so the rail reads as
    /// scrollable. On a phone it used to start right at the screen's edge, so
    /// it looked missing until the rail was swiped.
    func testSecondCardPeeksInWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "new"]
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "New.FeatureCard.Trending").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected the second featured card.")
        let shown = app.windows.firstMatch.frame.maxX - card.frame.minX
        XCTAssertGreaterThanOrEqual(shown, 24, "Only \(shown)pt of the second card is on screen.")
    }
}
