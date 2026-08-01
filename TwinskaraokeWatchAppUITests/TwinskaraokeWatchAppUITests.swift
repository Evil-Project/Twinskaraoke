import XCTest

final class TwinskaraokeWatchAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testWatchAppLaunches() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
  }

  func testWatchHomeShowsMusicSectionsAndSearchNavigation() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    XCTAssertTrue(
      app.staticTexts["Listen Now"].waitForExistence(timeout: 8)
        || app.otherElements["WatchHome.listenNow"].waitForExistence(timeout: 8),
      "Expected the compact Listen Now header to be visible."
    )

    scrollToVisibleItem("Playlists", identifier: "WatchHome.playlists", in: app)

    for item in ["Playlists", "Songs", "Search", "Account"] {
      XCTAssertTrue(
        app.staticTexts[item].waitForExistence(timeout: 8)
          || app.buttons[item].waitForExistence(timeout: 8),
        "Expected \(item) browse link to be visible on watch Home."
      )
    }

    openVisibleItem("Search", identifier: "WatchHome.search", in: app)
    XCTAssertTrue(
      app.navigationBars["Search"].waitForExistence(timeout: 8)
        || app.textFields["Search"].waitForExistence(timeout: 8)
        || app.staticTexts["Search"].waitForExistence(timeout: 8),
      "Expected Search screen to open from watch Home."
    )
  }

  func testWatchTrendingSongOpensPlayerInUITestMode() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "WatchHome.trending.0",
      in: app
    )

    XCTAssertTrue(
      app.navigationBars["Now Playing"].waitForExistence(timeout: 8)
        || app.staticTexts["Now Playing"].waitForExistence(timeout: 8),
      "Expected the watch player to open from a trending song."
    )
    let nowPlaying = app.descendants(matching: .any)["WatchPlayer.nowPlaying"]
    XCTAssertTrue(
      nowPlaying.waitForExistence(timeout: 8),
      "Expected the Now Playing metadata to be exposed."
    )
    XCTAssertTrue(
      String(describing: nowPlaying.value).contains("Wake Me Up Before You Go-Go"),
      "Expected the selected song title in the Now Playing accessibility value."
    )
    XCTAssertTrue(
      app.buttons["Play"].waitForExistence(timeout: 8)
        || app.buttons["Pause"].waitForExistence(timeout: 8)
        || app.buttons["Cancel Loading"].waitForExistence(timeout: 8),
      "Expected a primary playback control in the watch player."
    )
  }

  func testWatchPlayerOpensPlayingNextQueueInUITestMode() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "WatchHome.trending.0",
      in: app
    )

    XCTAssertTrue(
      app.navigationBars["Now Playing"].waitForExistence(timeout: 8)
        || app.staticTexts["Now Playing"].waitForExistence(timeout: 8),
      "Expected the watch player to open from a trending song."
    )

    scrollToVisibleItem("Playing Next", identifier: "WatchPlayer.queue", in: app)
    openVisibleItem("Playing Next", identifier: "WatchPlayer.queue", in: app)

    XCTAssertTrue(
      app.navigationBars["Queue"].waitForExistence(timeout: 8)
        || app.staticTexts["Queue"].waitForExistence(timeout: 8),
      "Expected the watch queue to open from the player."
    )
    XCTAssertTrue(
      app.otherElements["WatchQueue.summary"].waitForExistence(timeout: 8)
        || app.staticTexts["Playing Next"].waitForExistence(timeout: 8),
      "Expected the queue summary or Playing Next section to be visible."
    )
    scrollToVisibleItem("Hero", identifier: "WatchQueue.upNext.0", in: app)
    XCTAssertTrue(
      app.buttons["WatchQueue.upNext.0"].exists
        || app.otherElements["WatchQueue.upNext.0"].exists
        || app.staticTexts["Hero"].waitForExistence(timeout: 8),
      "Expected the next queued fixture song to be visible."
    )
  }

  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
    app.launch()
    return app
  }

  private func openVisibleItem(_ title: String, identifier: String, in app: XCUIApplication) {
    if app.buttons[identifier].waitForExistence(timeout: 5) {
      app.buttons[identifier].tap()
      return
    }

    if app.otherElements[identifier].waitForExistence(timeout: 5) {
      app.otherElements[identifier].tap()
      return
    }

    if app.buttons[title].waitForExistence(timeout: 5) {
      app.buttons[title].tap()
      return
    }

    let matchingCell = app.cells.containing(.staticText, identifier: title).firstMatch
    if matchingCell.waitForExistence(timeout: 5) {
      matchingCell.tap()
      return
    }

    let matchingText = app.staticTexts[title]
    XCTAssertTrue(matchingText.waitForExistence(timeout: 5), "Missing visible item \(title).")
    matchingText.tap()
  }

  private func scrollToVisibleItem(_ title: String, identifier: String, in app: XCUIApplication) {
    for _ in 0..<5 {
      if app.buttons[identifier].exists
        || app.otherElements[identifier].exists
        || app.staticTexts[title].exists
        || app.buttons[title].exists
      {
        return
      }
      app.swipeUp()
    }
    XCTAssertTrue(
      app.buttons[identifier].exists
        || app.otherElements[identifier].exists
        || app.staticTexts[title].exists
        || app.buttons[title].exists,
      "Missing visible item \(title) after scrolling."
    )
  }
}
