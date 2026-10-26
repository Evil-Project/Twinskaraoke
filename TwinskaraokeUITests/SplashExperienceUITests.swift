import XCTest

@MainActor final class SplashExperienceUITests: XCTestCase {
    /// Stops the UI test at its first assertion failure.
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(reset: Bool = true, update: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash"]
        if reset { app.launchArguments.append("-UITestSplashReset") }
        if update { app.launchArguments.append("-UITestSplashUpdate") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        return app
    }
    /// Verifies that mandatory gate rejects swipes and resumes after termination.
    func testMandatoryGateRejectsSwipesAndResumesAfterTermination() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 3")
        XCTAssertFalse(app.buttons["Splash.Complete"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
        app.swipeLeft(); app.swipeDown()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 3")
        XCTAssertFalse(app.tabBars.buttons["Library"].exists)
        app.buttons["Splash.Next"].tap()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 2 of 3")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 2 of 3")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-UITestSplashReset" }
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 2 of 3")
        app.buttons["Splash.Back"].tap()
        waitForProgress("Welcome, slide 1 of 3", in: app)
        app.buttons["Splash.Next"].tap()
        waitForProgress("Welcome, slide 2 of 3", in: app)
        app.buttons["Splash.Next"].tap()
        waitForProgress("Welcome, slide 3 of 3", in: app)
        XCTAssertTrue(app.buttons["Splash.Complete"].waitForExistence(timeout: 5))
        app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Splash.Progress"].exists)
    }
    /// Verifies that install then update and large text controls remain usable.
    func testInstallThenUpdateAndLargeTextControlsRemainUsable() {
        let app = launch(update: true, large: true)
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Update, slide 1 of 2")
        XCTAssertFalse(app.buttons["AccountToolbarButton"].exists)
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
    }
    /// Verifies that long light content scrolls and RTL navigation stays sequential.
    func testLongLightContentScrollsAndRTLNavigationStaysSequential() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashReset", "-UITestSplashLongContent", "-UITestSplashRTL", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Splash.Next"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Splash.Next"].isHittable)
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 3")
        XCTAssertTrue(app.buttons["Splash.Next"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["Splash.Next"].tap()
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 2 of 3")
        XCTAssertLessThan(app.buttons["Splash.Next"].frame.minX, app.buttons["Splash.Back"].frame.minX)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Splash.Complete"].exists)
    }
    /// Verifies that developer unlock studio preview and export cancellation.
    func testDeveloperUnlockStudioPreviewAndExportCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1"]
        app.launch()
        let account = app.buttons["AccountToolbarButton"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 15)); account.tap()
        tap("About", app: app)
        let version = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Version '")).firstMatch
        for _ in 0..<8 { if version.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        unlock(version, in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("Settings", app: app)
        // If a prior run had developer mode enabled, the 20 taps toggled it off.
        var developer = app.staticTexts["Developer"].firstMatch
        for _ in 0..<8 { if developer.isHittable { break }; app.swipeUp() }
        if !developer.exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tap("About", app: app)
            unlock(version, in: app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tap("Settings", app: app)
            developer = app.staticTexts["Developer"].firstMatch
        }
        tap("Developer", app: app)
        tap("Splash Screen Studio", app: app)
        XCTAssertTrue(app.navigationBars["Splash Screen Studio"].waitForExistence(timeout: 8))
        let preview = app.buttons["SplashStudio.Preview"]
        for _ in 0..<10 { if preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable); preview.tap()
        XCTAssertTrue(app.buttons["Exit Preview"].waitForExistence(timeout: 8))
        app.buttons["Exit Preview"].tap()
        let export = app.buttons["SplashStudio.Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5)); export.tap()
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        if !cancel.waitForExistence(timeout: 8) {
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
            XCTFail("Exporter Cancel missing. UI: \(app.debugDescription)"); return
        }
        // iOS 26's Files provider exposes a stale Cancel frame. Use the visible
        // leading close control, aligned with the system Save button.
        let pickerSave = app.buttons["Save"].firstMatch
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 5))
        let closeY = pickerSave.frame.midY
        // On iPhone the first leading control returns to Browse; the next closes.
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 32, dy: closeY)).tap()
            if cancel.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(pickerSave.waitForNonExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Splash Screen Studio"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Export succeeded'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["SplashStudio.Preview"].exists)
        for _ in 0..<10 { if export.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(export.isHittable); export.tap()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription); save.tap()
        if app.alerts.buttons["Replace"].waitForExistence(timeout: 2) { app.alerts.buttons["Replace"].tap() }
        let exported = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Export succeeded'")).firstMatch
        XCTAssertTrue(exported.waitForExistence(timeout: 10), app.debugDescription)
        tap("Import JSON", app: app)
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'install.json,' OR label BEGINSWITH[c] 'install,'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        // Select the file's icon rather than its editable filename caption.
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["Imported into the draft."].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let picker = app.descendants(matching: .any).matching(identifier: "Developer.SplashTesting").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        app.buttons["Update"].firstMatch.tap()
        XCTAssertTrue(picker.exists)
        picker.tap(); app.buttons["Off"].firstMatch.tap()
    }
    /// Waits for persisted slide navigation to appear before sending another action.
    private func waitForProgress(_ label: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: app.staticTexts["Splash.Progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    /// Performs the version-tap sequence to enable the hidden Developer menu.
    private func unlock(_ version: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { version.tap() }
        if app.buttons["Close"].waitForExistence(timeout: 5) { app.buttons["Close"].tap() }
        for _ in 0..<10 { version.tap() }
    }
    /// Launches the isolated Studio fixture without changing real walkthrough history.
    private func launchStudio() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplashStudio", "-UITestSplashStudioReset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Splash Screen Studio"].waitForExistence(timeout: 15))
        return app
    }
    /// Verifies that studio save bubble canvas and single slide preview.
    func testStudioSaveBubbleCanvasAndSingleSlidePreview() {
        let app = launchStudio()
        tap("Save Local Draft", app: app)
        let notice = app.staticTexts["Draft saved locally."]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertLessThan(notice.frame.midY, app.frame.height / 2)
        scrollForm(app, up: false); scrollForm(app, up: false)
        tap("1. Slide title", app: app)
        tap("Arrange on Canvas", app: app)
        let canvas = app.descendants(matching: .any)["SplashStudio.Canvas"].firstMatch
        XCTAssertGreaterThan(canvas.frame.height, app.frame.height * 0.65)
        XCTAssertFalse(app.sliders["SplashStudio.PositionY"].exists)
        let title = app.descendants(matching: .any)["SplashCanvas.title"].firstMatch
        XCTAssertTrue(title.exists, app.debugDescription)
        let origin = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 45)))
        tap("SplashStudio.EditSelected", app: app)
        let position = app.sliders["SplashStudio.PositionY"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["SplashStudio.CanvasSelection"].label, "Selected Item, Title")
        XCTAssertNotEqual(Double(position.value as? String ?? ""), 0.48)
        tap("Center Vertically", app: app)
        XCTAssertEqual(Double(position.value as? String ?? ""), 0.5)
        tap("SplashStudio.TextSize-Increment", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["SplashStudio.CanvasInspector"].firstMatch.steppers["SplashStudio.TextSize"].value as? String, "35")
        tap("Font, System", app: app)
        app.buttons["Serif"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["SplashStudio.CanvasInspector"].firstMatch.buttons["Font, Serif"].exists)
        app.buttons["Done Editing"].tap()
        XCTAssertGreaterThan(canvas.frame.height, app.frame.height * 0.65)
        tap("Preview Slide", app: app)
        XCTAssertTrue(app.buttons["Exit Preview"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 1")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["Exit Preview"].tap()
        app.buttons["Done"].tap()
    }
    /// Verifies that files image import and rounded preview.
    func testFilesImageImportAndRoundedPreview() {
        let app = launchStudio()
        app.buttons["Export Test Image"].tap()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        if app.alerts.buttons["Replace"].waitForExistence(timeout: 2) { app.alerts.buttons["Replace"].tap() }
        XCTAssertTrue(app.staticTexts["Test image exported."].waitForExistence(timeout: 8))
        tap("1. Slide title", app: app)
        tap("Import Image from Files", app: app)
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "walkthrough-test-image")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["Image resized and embedded."].waitForExistence(timeout: 8), app.debugDescription)
        let corners = app.sliders["SplashStudio.Corners"]
        reveal(corners, app: app)
        XCTAssertTrue(corners.isHittable); corners.adjust(toNormalizedSliderPosition: 0.3)
        let preview = app.buttons["SplashStudio.SinglePreview"]
        for _ in 0..<20 where !preview.isHittable { scrollForm(app, up: false) }
        XCTAssertTrue(preview.isHittable, app.debugDescription); preview.tap()
        XCTAssertTrue(app.buttons["Exit Preview"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["Exit Preview"].tap()
    }
    /// Verifies that mock interactions advance only the demonstration.
    func testMockInteractionsAdvanceOnlyTheDemonstration() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashReset", "-UITestSplashDesign"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        tap("Add demo favorite", app: app)
        XCTAssertTrue(app.buttons["Remove demo favorite"].exists)
        let sequence = app.descendants(matching: .any)["SplashDemo.Sequence"].firstMatch
        for _ in 0..<5 where !sequence.buttons["Play demo"].isHittable { app.swipeUp() }
        XCTAssertTrue(sequence.buttons["Play demo"].isHittable, app.debugDescription)
        sequence.buttons["Play demo"].tap()
        XCTAssertTrue(app.staticTexts["SplashDemo.Progress"].label.contains("2 of 2"))
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 3")
        XCTAssertFalse(app.buttons["AccountToolbarButton"].exists)
        app.buttons["Splash.Next"].tap(); app.buttons["Splash.Next"].tap(); app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
    }

    /// Verifies that canvas grid pinch and corner resizing.
    func testCanvasGridPinchAndCornerResizing() {
        let app = launchStudio()
        tap("1. Slide title", app: app); tap("Arrange on Canvas", app: app)
        app.descendants(matching: .any)["SplashStudio.Grid"].firstMatch.tap()
        tap("SplashStudio.EditSelected", app: app)
        let boxHeight = app.sliders["SplashStudio.BoxHeight"]
        for _ in 0..<8 where !boxHeight.isHittable { scrollForm(app, up: true) }
        XCTAssertTrue(boxHeight.isHittable)
        boxHeight.adjust(toNormalizedSliderPosition: 0.2)
        app.buttons["Done Editing"].tap()
        let title = app.descendants(matching: .any)["SplashCanvas.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = title.frame.width
        title.pinch(withScale: 0.75, velocity: -1)
        XCTAssertLessThan(title.frame.width, before)
        let contracted = title.frame.width
        title.pinch(withScale: 1.2, velocity: 1)
        XCTAssertGreaterThan(title.frame.width, contracted)
        let corner = title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.9))
        let height = title.frame.height
        corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: -20, dy: 65)))
        XCTAssertGreaterThan(title.frame.height, height)
        let center = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -120)))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        tap("SplashStudio.EditSelected", app: app)
        let position = app.sliders["SplashStudio.PositionY"]
        for _ in 0..<8 where !position.isHittable { scrollForm(app, up: true) }
        XCTAssertTrue(position.isHittable, app.debugDescription)
        let y = Double(position.value as? String ?? "") ?? -1
        XCTAssertTrue((0.05...0.95).contains(y))
        XCTAssertNotEqual(y, 0.5)
        XCTAssertEqual(y / 0.05, (y / 0.05).rounded(), accuracy: 0.001)
        app.buttons["Done Editing"].tap()
        app.descendants(matching: .any)["SplashStudio.Grid"].firstMatch.tap()
        app.buttons["Done"].tap()
    }
    /// Verifies that bundled image and background assets preview.
    func testBundledImageAndBackgroundAssetsPreview() {
        let app = launchStudio()
        tap("1. Slide title", app: app)
        tap("Choose Bundled Asset", app: app)
        XCTAssertTrue(app.buttons["SplashAsset.twins"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["App Screenshots"].exists)
        XCTAssertFalse(app.staticTexts["Shimeji Static Poses"].exists)
        app.buttons["SplashAsset.twins"].tap()
        XCTAssertTrue(app.staticTexts["Bundled asset embedded."].waitForExistence(timeout: 5))
        tap("Choose Background Asset", app: app)
        app.buttons["SplashAsset.wide-banner"].tap()
        let dim = app.sliders["SplashStudio.BackgroundDim"]
        for _ in 0..<8 where !dim.isHittable { scrollForm(app, up: true) }
        XCTAssertTrue(dim.isHittable, app.debugDescription)
        dim.adjust(toNormalizedSliderPosition: 0.65)
        for _ in 0..<25 where !app.buttons["SplashStudio.SinglePreview"].isHittable { scrollForm(app, up: false) }
        app.buttons["SplashStudio.SinglePreview"].tap()
        XCTAssertTrue(app.buttons["Exit Preview"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["Exit Preview"].tap()
    }
    /// Verifies that proposed install loads and previews all eight slides.
    func testProposedInstallLoadsAndPreviewsAllEightSlides() {
        let app = launchStudio()
        tap("Load Proposed Install Walkthrough", app: app)
        app.buttons["Load Proposal"].tap()
        tap("Preview", app: app)
        XCTAssertTrue(app.buttons["Exit Preview"].waitForExistence(timeout: 5))
        for index in 1...8 {
            XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide \(index) of 8")
            if index == 1 || index == 7 {
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            }
            if index < 8 { app.buttons["Splash.Next"].tap() }
        }
        XCTAssertTrue(app.staticTexts["Made possible by the community"].exists)
        app.buttons["Splash.Complete"].tap()
        XCTAssertTrue(app.navigationBars["Splash Screen Studio"].waitForExistence(timeout: 5))
    }

    /// Verifies that developer resets each walkthrough and closes app.
    func testDeveloperResetsEachWalkthroughAndClosesApp() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestSplash", "-UITestSplashReset", "-UITestSplashUpdate", "-UITestSplashResetControls"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        finishVisibleWalkthroughs(app)
        openDeveloper(app)
        tap("Developer.ResetUpdateSplash", app: app)
        app.buttons["Reset & Close App"].tap()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments.removeAll { $0 == "-UITestSplashReset" }
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Update, slide 1 of 2")
        finishVisibleWalkthroughs(app)
        openDeveloper(app)
        tap("Developer.ResetInstallSplash", app: app)
        app.buttons["Reset & Close App"].tap()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        XCTAssertTrue(app.staticTexts["Splash.Progress"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["Splash.Progress"].label, "Welcome, slide 1 of 3")
        finishVisibleWalkthroughs(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Splash.Progress"].exists)
    }
    /// Completes each visible fixture walkthrough using its sequential navigation buttons.
    private func finishVisibleWalkthroughs(_ app: XCUIApplication) {
        for _ in 0..<8 {
            if app.buttons["AccountToolbarButton"].firstMatch.exists { break }
            if app.buttons["Splash.Next"].exists { app.buttons["Splash.Next"].tap() }
            else if app.buttons["Splash.Complete"].exists { app.buttons["Splash.Complete"].tap() }
        }
        XCTAssertTrue(app.buttons["AccountToolbarButton"].firstMatch.waitForExistence(timeout: 15))
    }
    /// Navigates from Account settings to the Developer menu.
    private func openDeveloper(_ app: XCUIApplication) {
        app.buttons["AccountToolbarButton"].firstMatch.tap()
        tap("Settings", app: app); tap("Developer", app: app)
    }
    /// Small drags keep short controls from being skipped after image rows expand.
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        var up = true
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            let canvas = app.descendants(matching: .any)["SplashStudio.CanvasInspector"].firstMatch
            let slide = app.descendants(matching: .any)["SplashStudio.SlideForm"].firstMatch
            let form = canvas.exists ? canvas : (slide.exists ? slide : app.collectionViews.firstMatch)
            guard form.exists else { return }
            if element.exists {
                up = element.frame.midY > form.frame.midY
            }
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.65 : 0.4))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
    /// Scrolls the visible canvas inspector or slide form in the requested direction.
    private func scrollForm(_ app: XCUIApplication, up: Bool) {
        let canvas = app.descendants(matching: .any)["SplashStudio.CanvasInspector"].firstMatch
        let slide = app.descendants(matching: .any)["SplashStudio.SlideForm"].firstMatch
        let form = canvas.exists ? canvas : (slide.exists ? slide : app.collectionViews.firstMatch)
        guard form.exists else { if up { app.swipeUp() } else { app.swipeDown() }; return }
        if up { form.swipeUp(velocity: .slow) } else { form.swipeDown(velocity: .slow) }
    }
    /// Finds and taps the named control in the active inspector or slide form.
    private func tap(_ label: String, app: XCUIApplication) {
        for _ in 0..<10 {
            let inspector = app.descendants(matching: .any)["SplashStudio.CanvasInspector"].firstMatch
            let scope: XCUIElement = inspector.exists ? inspector : app
            let button = scope.buttons[label].firstMatch
            if button.exists && button.isHittable { button.tap(); return }
            let cell = scope.cells.containing(.staticText, identifier: label).firstMatch
            if cell.exists && cell.isHittable { cell.tap(); return }
            let text = scope.staticTexts[label].firstMatch
            if text.exists && text.isHittable { text.tap(); return }
            scrollForm(app, up: true)
        }
        XCTFail("Missing \(label): \(app.debugDescription)")
    }
}
