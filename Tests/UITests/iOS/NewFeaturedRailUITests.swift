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
}
