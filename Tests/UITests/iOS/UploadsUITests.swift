import XCTest

/// Library → Uploaded on the `-UITestMode` fixtures: a signed-in user's
/// uploads, the upload sheet, and a link import that runs against the
/// controller's fixture service. Nothing reaches the network, and the
/// system file browser isn't driven.
@MainActor
final class UploadsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUploadedShowsUploadButtonAndFixtureSongs() throws {
        let app = openUploaded()
        XCTAssertTrue(app.buttons["Uploads.Add"].waitForExistence(timeout: 8), "Expected the Upload Song button for a signed-in user.")
        XCTAssertEqual(app.buttons["Uploads.Add"].label, "Upload Song")
        XCTAssertTrue(row("Moonlight Densetsu", in: app).waitForExistence(timeout: 8), "Expected the fixture uploads.")
        XCTAssertTrue(row("Snow halation", in: app).exists)
        XCTAssertFalse(app.staticTexts["Sign In Required"].exists)
    }

    func testUploadSheetStartsWithUploadDisabled() throws {
        let app = openUploaded()
        openSheet(in: app)
        let submit = app.buttons["UploadSong.Submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertEqual(submit.label, "Upload")
        XCTAssertFalse(submit.isEnabled, "Upload needs a file first.")
        XCTAssertTrue(app.buttons["UploadSong.ChooseFile"].exists)
        XCTAssertTrue(app.staticTexts["Songs Uploaded"].waitForExistence(timeout: 5), "Expected the storage section.")
    }

    func testLinkModeEnablesImportForSupportedLink() throws {
        let app = openUploaded()
        openSheet(in: app)
        let field = switchToLink(in: app)
        let submit = app.buttons["UploadSong.Submit"]
        XCTAssertEqual(submit.label, "Import")
        XCTAssertFalse(submit.isEnabled)

        field.typeText("https://discord.com/channels/1/2/3")
        let problem = element("UploadSong.LinkProblem", in: app)
        XCTAssertTrue(problem.waitForExistence(timeout: 3), "Expected the Discord message link to be explained.")
        XCTAssertTrue(problem.label.localizedCaseInsensitiveContains("attachment"), "Got: \(problem.label)")
        XCTAssertFalse(submit.isEnabled)

        clear(field)
        field.typeText("https://youtu.be/dQw4w9WgXcQ")
        XCTAssertTrue(waitUntil(timeout: 3) { submit.isEnabled }, "Expected Import to turn on for a YouTube link.")
        XCTAssertFalse(problem.exists)
    }

    func testLinkImportShowsProgressThenSongRefresh() throws {
        let app = openUploaded()
        XCTAssertTrue(row("Moonlight Densetsu", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(row("UI Test Link Song", in: app).exists)
        openSheet(in: app)
        let field = switchToLink(in: app)
        field.typeText("https://youtu.be/dQw4w9WgXcQ")
        let submit = app.buttons["UploadSong.Submit"]
        XCTAssertTrue(waitUntil(timeout: 3) { submit.isEnabled })
        submit.tap()

        let status = element("Uploads.Progress.Status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Expected a progress row once the sheet closes.")
        XCTAssertTrue(status.label.contains("Importing"), "Got: \(status.label)")
        XCTAssertTrue(app.buttons["Uploads.Progress.Cancel"].exists, "A running import can be cancelled.")

        XCTAssertTrue(
            row("UI Test Link Song", in: app).waitForExistence(timeout: 10),
            "Expected the list to refresh with the imported song."
        )
        XCTAssertTrue(waitUntil(timeout: 3) { status.label.contains("Added") }, "Got: \(status.label)")
    }

    // MARK: - Helpers

    private func openUploaded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "library"]
        app.launch()
        let link = app.buttons["Uploaded"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Expected the Uploaded link in Library.")
        if !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(element("Library.UploadedSongs", in: app).waitForExistence(timeout: 8))
        return app
    }

    private func openSheet(in app: XCUIApplication) {
        let add = app.buttons["Uploads.Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        XCTAssertTrue(app.navigationBars["Upload a Song"].waitForExistence(timeout: 5), "Expected the upload sheet.")
    }

    private func switchToLink(in app: XCUIApplication) -> XCUIElement {
        let link = app.segmentedControls.buttons["Link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let field = app.textFields["UploadSong.Link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { app.keyboards.firstMatch.exists }, "Expected the keyboard for the link field.")
        return field
    }

    private func clear(_ field: XCUIElement) {
        let text = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }

    /// A song row in the list; its title leads the row's combined label.
    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
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
