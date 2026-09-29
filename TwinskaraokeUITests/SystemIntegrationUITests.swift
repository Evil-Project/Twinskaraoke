import XCTest

@MainActor
final class SystemIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeepLinksSelectRootDestinations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestResetRecentlyPlayed"]
        app.launch()
        for (route, title) in [("search", "Search"), ("library", "Library"), ("radio", "Radio"), ("home", "Home")] {
            app.open(URL(string: "twinskaraoke://\(route)")!)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10) || app.staticTexts[title].waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Deep link \(route)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testColdLaunchSearchRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        app.terminate()
        app.open(URL(string: "twinskaraoke://search")!)
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 15) || app.staticTexts["Featured"].waitForExistence(timeout: 10))
    }
    func testPlaylistLinkOpensTheSelectedPlaylist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestResetRecentlyPlayed"]
        app.launch()
        let playlist = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Karaoke Essentials")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 15))
        playlist.tap()
        let song = app.descendants(matching: .any).matching(identifier: "PlaylistDetail.song.0.ui-home-song-1").firstMatch
        for _ in 0..<4 {
            if song.exists && song.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        // Playlist gestures arm after the navigation transition completes.
        let miniPlayer = app.descendants(matching: .any).matching(identifier: "MiniPlayerBar").firstMatch
        for _ in 0..<3 {
            song.tap()
            if miniPlayer.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(miniPlayer.exists, "Playback must record the selected playlist before testing its recent-playlist link.")
        app.launchArguments = ["-UITestMode"]
        app.open(URL(string: "twinskaraoke://playlist/ui-home-playlist-essentials")!)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Karaoke Essentials"].firstMatch.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Playlist widget destination"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
