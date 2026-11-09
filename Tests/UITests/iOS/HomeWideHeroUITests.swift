import XCTest

/// The iPad Home hero's quick actions say what they play, on the
/// `-UITestMode` fixtures.
@MainActor
final class HomeWideHeroUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// The fixtures have Made for You, so Shuffle Mix shuffles it. The row
    /// used to show the second Made for You song ("Hero") instead.
    func testShuffleMixNamesTheListItShuffles() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The wide Home hero is only shown on iPad."
        )
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home"]
        app.launch()

        let hero = app.descendants(matching: .any).matching(identifier: "Home.WideHero").firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 15), "Expected the wide Home hero.")

        let shuffleMix = hero.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Shuffle Mix")).firstMatch
        XCTAssertTrue(shuffleMix.waitForExistence(timeout: 8), "Expected the Shuffle Mix row.")
        XCTAssertTrue(
            shuffleMix.label.contains("Made for You"),
            "Shuffle Mix names the list it shuffles; its label was \"\(shuffleMix.label)\"."
        )
    }
}
