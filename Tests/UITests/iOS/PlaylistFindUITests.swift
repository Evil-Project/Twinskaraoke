import XCTest

/// "Find in Playlist" without the pull: the field is otherwise revealed only
/// by pulling the list past its top, which VoiceOver, Switch Control and a
/// hardware keyboard can't do.
///
/// ⌘F has no test here: `typeKey(_:modifierFlags:)` reached no keyboard
/// shortcut in the simulator, not even one on a visible toolbar button.
@MainActor
final class PlaylistFindUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMoreMenuOpensAndFocusesTheFindField() throws {
        let app = openFixturePlaylist()
        let field = findField(in: app)
        XCTAssertFalse(field.isHittable, "The field starts collapsed.")

        let moreActions = app.buttons["PlaylistDetail.moreActions"]
        XCTAssertTrue(moreActions.waitForExistence(timeout: 8), "Expected the playlist actions menu.")
        moreActions.tap()
        // By identifier: the invisible ⌘F carrier has the same title.
        let find = app.buttons["PlaylistDetail.find"]
        XCTAssertTrue(find.waitForExistence(timeout: 5), "Expected Find in Playlist in the actions menu.")
        find.tap()

        XCTAssertTrue(waitUntil(timeout: 5) { field.isHittable }, "Expected the find field to open.")
        XCTAssertTrue(
            waitUntil(timeout: 5) { field.value(forKey: "hasKeyboardFocus") as? Bool == true },
            "Expected the find field to take focus."
        )
    }

    private func openFixturePlaylist() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "search"]
        app.launch()
        tap("SearchCategory.PublicPlaylists", in: app)
        tap("PlaylistList.ui-search-playlist-essentials", in: app)
        XCTAssertTrue(
            element("PlaylistDetail.song.0.ui-search-song-1", in: app).waitForExistence(timeout: 8),
            "Expected the fixture playlist to open."
        )
        return app
    }

    /// The container's `PlaylistDetail.search` identifier is what the text
    /// field reports; the field's own `PlaylistDetail.searchField` doesn't
    /// reach the accessibility tree.
    private func findField(in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: "PlaylistDetail.search").firstMatch
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let target = element(identifier, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier).")
        target.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
