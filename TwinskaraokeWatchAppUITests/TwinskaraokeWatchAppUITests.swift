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

    // Checked one at a time: the Browse section is taller than the screen, so
    // only a few cells are ever in the hierarchy together and asserting them
    // all at once would depend on how many rows happen to fit.
    let browseLinks = [
      ("Playlists", "WatchHome.playlists"),
      ("Radio", "WatchHome.radio"),
      ("Songs", "WatchHome.songs"),
      ("Search", "WatchHome.search"),
      ("Account", "WatchHome.account"),
    ]
    for (title, identifier) in browseLinks {
      scrollToVisibleItem(title, identifier: identifier, in: app)
      XCTAssertTrue(
        isVisible(title, identifier: identifier, in: app),
        "Expected \(title) browse link to be reachable on watch Home."
      )
    }

    openVisibleItem("Search", identifier: "WatchHome.search", in: app)
    // Asserted on the empty state's message, not on "Search": that word is also
    // the label of the Home row we just tapped, so matching it proved only that
    // we were still looking at Home. That is how a stack that pushed nothing at
    // all went green.
    XCTAssertTrue(
      app.staticTexts["Find songs, artists, and new favorites."].waitForExistence(timeout: 8),
      "Expected Search screen to open from watch Home."
    )
    XCTAssertFalse(
      app.staticTexts["Listen Now"].exists,
      "Expected to have left Home rather than stayed on it."
    )
  }

  /// Account has no network content to assert on, so this checks the only
  /// thing that actually broke: that tapping the row leaves Home at all.
  /// A fresh launch per destination avoids depending on the back gesture.
  func testWatchAccountLinkPushesFromHome() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    scrollToVisibleItem("Account", identifier: "WatchHome.account", in: app)
    openVisibleItem("Account", identifier: "WatchHome.account", in: app)

    XCTAssertTrue(
      app.staticTexts["Guest Listener"].waitForExistence(timeout: 8)
        || app.staticTexts["Guest ID"].waitForExistence(timeout: 8),
      "Expected the Account screen to open from watch Home."
    )
    XCTAssertFalse(
      app.staticTexts["Listen Now"].exists,
      "Expected to have left Home rather than stayed on it."
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
    XCTAssertTrue(
      app.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected the selected song title to be visible in the watch player."
    )
    XCTAssertTrue(
      app.buttons["Play"].waitForExistence(timeout: 8)
        || app.buttons["Pause"].waitForExistence(timeout: 8),
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

    // The player is one fixed screenful now, so the queue button is on screen
    // without scrolling — and the queue is a page beside it rather than a push.
    openVisibleItem("Playing Next", identifier: "WatchPlayer.queue", in: app)

    XCTAssertTrue(
      app.navigationBars["Playing Next"].waitForExistence(timeout: 8)
        || app.staticTexts["Playing Next"].waitForExistence(timeout: 8),
      "Expected the queue page to show beside the player."
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

  /// Scrolls a watch list until `title` is in the hierarchy.
  ///
  /// The Digital Crown moves in small, predictable steps, unlike a swipe: a
  /// flick carries a 248pt screen clean past the target, and a row that scrolls
  /// out is recycled out of the accessibility hierarchy, so `exists` never
  /// recovers. Each lookup rewinds to the top first so it does not depend on
  /// where a previous lookup left the list.
  private func scrollToVisibleItem(_ title: String, identifier: String, in app: XCUIApplication) {
    if isVisible(title, identifier: identifier, in: app) {
      return
    }
    // Scan downwards first: callers walk a screen top to bottom, so the target
    // is almost always below where the last lookup stopped.
    for _ in 0..<12 {
      XCUIDevice.shared.rotateDigitalCrown(delta: 0.4)
      if isVisible(title, identifier: identifier, in: app) {
        return
      }
    }
    // Not below: rewind to the top and sweep the whole list once.
    XCUIDevice.shared.rotateDigitalCrown(delta: -12)
    for _ in 0..<24 {
      if isVisible(title, identifier: identifier, in: app) {
        return
      }
      XCUIDevice.shared.rotateDigitalCrown(delta: 0.4)
    }
    XCTAssertTrue(
      isVisible(title, identifier: identifier, in: app),
      "Missing visible item \(title) after scrolling."
    )
  }

  private func isVisible(_ title: String, identifier: String, in app: XCUIApplication) -> Bool {
    app.buttons[identifier].exists
      || app.otherElements[identifier].exists
      || app.staticTexts[title].exists
      || app.buttons[title].exists
  }
}
