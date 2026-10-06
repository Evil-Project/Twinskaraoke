import XCTest

@MainActor
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

  func testWatchAccountHasNoSignInAction() throws {
    let app = launchApp()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    scrollToVisibleItem("Account", identifier: "WatchHome.account", in: app)
    openVisibleItem("Account", identifier: "WatchHome.account", in: app)
    XCTAssertTrue(app.staticTexts["Guest Listener"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["WatchAccount.signInOnPhone"].exists)
    XCTAssertFalse(app.buttons["Sign in on iPhone"].exists)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
  }

  func testWatchTrendingSongOpensPlayerInUITestMode() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "WatchHome.trending.0",
      in: app
    )

    dismissPlaybackError(in: app)
    // Asserted on the song and its transport rather than on a "Now Playing"
    // title: the player page no longer carries one, because watchOS drew it
    // over the artwork instead of above it.
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
      app.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected the watch player to open from a trending song."
    )

    dismissPlaybackError(in: app)
    // The player is one fixed screenful now, so the queue button is on screen
    // without scrolling — and the queue is a page beside it rather than a push.
    app.swipeLeft()

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

  // A "Listen Live starts and stays tuned in" test used to live here. It cost
  // roughly eleven minutes and could not earn them: a simulator streams over
  // the Mac's network with no media daemon to stall on, so it never reproduced
  // the main-actor freeze the off-actor tune-in was written to fix. The
  // behaviour it was reaching for has to be confirmed on a wrist.

  // A Crown volume-direction test used to live here, and it was worse than
  // nothing. `XCUIDevice.rotateDigitalCrown(delta:)` raises the reported Crown
  // position for a positive delta; a watch on an arm does not agree, so the
  // test cheerfully confirmed whichever mapping was shipped -- three times, on
  // three devices, while the volume was audibly backwards. The mapping is
  // arithmetic and is now pinned by `WatchCrownVolumeTests` in milliseconds;
  // which way a physical Crown turns is a question only a wrist can answer.

  func testWatchDownloadsAndOutputOptionsOpen() throws {
    let app = launchApp()
    scrollToVisibleItem("Downloads", identifier: "WatchHome.downloads", in: app)
    openVisibleItem("Downloads", identifier: "WatchHome.downloads", in: app)
    XCTAssertTrue(app.staticTexts["Playback Device"].waitForExistence(timeout: 8) || app.buttons["WatchPlayback.output"].exists)
    scrollToVisibleItem("No Downloads", identifier: "No Downloads", in: app)
    XCTAssertTrue(app.staticTexts["No Downloads"].exists)
    saveScreenshot(app, name: "Watch Downloads")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
  }

  func testWatchPlayerOutputSheetOpens() throws {
    let app = launchApp()
    openVisibleItem("Wake Me Up Before You Go-Go", identifier: "WatchHome.trending.0", in: app)
    dismissPlaybackError(in: app)
    let output = app.buttons["WatchPlayer.options"].firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 8))
    output.tap()
    XCTAssertTrue(app.staticTexts["Options"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons["Sleep Timer"].exists)
    XCTAssertTrue(app.buttons["Download to Watch"].exists, "Songs without inline audio metadata must allow a resolving download.")
    saveScreenshot(app, name: "Watch Output Options")
  }

  func testWatchCachedSongPlaybackDoesNotCrash() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestLocalAudio"]
    app.launch()
    openVisibleItem("Wake Me Up Before You Go-Go", identifier: "WatchHome.trending.0", in: app)
    let playing = app.buttons["Pause"].firstMatch.waitForExistence(timeout: 15)
    if !playing {
      XCTAssertTrue(app.staticTexts["Playback Unavailable"].firstMatch.exists,
                    "A validated cached song must play or show an actionable audio-session error.")
      dismissPlaybackError(in: app)
    } else {
      app.buttons["Pause"].firstMatch.tap()
      XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5))
      app.buttons["Play"].firstMatch.tap()
      XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 5))
      app.buttons["Next Track"].firstMatch.tap()
      XCTAssertTrue(app.staticTexts["Hero"].waitForExistence(timeout: 8))
    }
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    saveScreenshot(app, name: "Watch Cached Audio Playback")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    app.terminate()
  }

  func testWatchTouchSeekingAndSleepTimerStatus() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestLocalAudio"]
    app.launch()
    defer { app.terminate() }
    openVisibleItem("Wake Me Up Before You Go-Go", identifier: "WatchHome.trending.0", in: app)
    XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 15), "Standalone cached audio must actually start.")
    app.buttons["Pause"].firstMatch.tap()
    let position = app.otherElements["WatchPlayer.position"].firstMatch
    XCTAssertTrue(position.waitForExistence(timeout: 5))
    position.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS '0:15'"), object: position)], timeout: 5) == .completed)
    XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
    XCTAssertTrue((position.value as? String)?.contains("0:15") == true,
                  "Volume Crown input must not change the paused playback position.")
    app.buttons["WatchPlayer.options"].tap()
    app.buttons["Sleep Timer"].firstMatch.tap()
    XCTAssertTrue(app.buttons["15 minutes"].waitForExistence(timeout: 5))
    app.buttons["15 minutes"].tap()
    let status = app.staticTexts["WatchPlayer.sleepStatus"].firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    XCTAssertTrue(status.isHittable)
    XCTAssertTrue(status.label.contains("remaining"))
    scrollToVisibleItem("When Current Song Ends", identifier: "", in: app)
    app.buttons["When Current Song Ends"].tap()
    XCTAssertTrue(app.staticTexts["End of song"].waitForExistence(timeout: 5))
    saveScreenshot(app, name: "Watch Sleep Timer Status")
  }

  func testWatchSavedDownloadsPlayLocally() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestDownloadedAudio"]
    app.launch()
    defer { app.terminate() }
    scrollToVisibleItem("Downloads", identifier: "WatchHome.downloads", in: app)
    openVisibleItem("Downloads", identifier: "WatchHome.downloads", in: app)
    XCTAssertTrue(app.buttons["Wake Me Up Before You Go-Go"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Wake Me Up Before You Go-Go"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 15),
                  "Persisted watch downloads must play without a phone or remote audio URL.")
    app.buttons["Next Track"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Hero"].waitForExistence(timeout: 8))
    saveScreenshot(app, name: "Watch Offline Download Playback")
  }

  func testWatchAccountClearsPersistentDownloads() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestDownloadedAudio"]
    app.launch()
    defer { app.terminate() }
    scrollToVisibleItem("Account", identifier: "WatchHome.account", in: app)
    openVisibleItem("Account", identifier: "WatchHome.account", in: app)
    scrollToVisibleItem("Clear Cache", identifier: "WatchAccount.clearAudio", in: app)
    let clear = app.buttons["WatchAccount.clearAudio"]
    XCTAssertTrue(clear.isEnabled, "Saved downloads must be counted even with an empty temporary cache.")
    clear.tap()
    XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 5))
    app.buttons["Clear"].tap()
    XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == false"), object: clear)], timeout: 5) == .completed)
    saveScreenshot(app, name: "Watch Account Audio Cleared")
  }

  private func dismissPlaybackError(in app: XCUIApplication) {
    // This fixture watch has no connected phone. Its actionable playback
    // error is expected; dismiss it before testing the controls underneath.
    if app.staticTexts["Playback Unavailable"].firstMatch.waitForExistence(timeout: 3) {
      app.buttons["OK"].firstMatch.tap()
    }
  }

  private func saveScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
    app.launch()
    return app
  }

  private func openVisibleItem(_ title: String, identifier: String, in app: XCUIApplication) {
    if app.buttons[identifier].waitForExistence(timeout: 5) {
      let button = app.buttons[identifier]
      XCTAssertTrue(NSPredicate(format: "isHittable == true").evaluate(with: button) ||
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: button)], timeout: 5) == .completed)
      button.tap()
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

  /// One turn of the Crown, in list terms.
  ///
  /// `rotateDigitalCrown` blocks for about 5.4 seconds whatever delta it is
  /// handed, so the only thing that makes a scroll cheap is asking for fewer,
  /// larger turns. Half a rotation moves a watch list by roughly a screenful:
  /// measured on Home, where one `+0.5` from the top brings the whole Browse
  /// section into the hierarchy and a second reaches the bottom.
  private static let crownScrollStep = 0.5

  /// Turns needed to cross the longest list under test, with room to spare.
  private static let crownScrollSpan = 4

  /// Scrolls a watch list until `title` is in the hierarchy.
  ///
  /// The Crown moves in predictable steps, unlike a swipe: a row that scrolls
  /// out is recycled out of the accessibility hierarchy, so overshooting a
  /// target means `exists` never recovers on the way past.
  ///
  /// Positive is *down* the list. This is measured, not read off the
  /// documentation, which describes the sign in terms of scroll direction
  /// rather than value: `+0.5` from the top of Home reveals the Browse rows
  /// and `-0.5` puts them away again. The helper used to scan with a negative
  /// delta, which held it against the top stop for thirty-six turns — three
  /// minutes of doing nothing, and then a failure.
  private func scrollToVisibleItem(_ title: String, identifier: String, in app: XCUIApplication) {
    if isVisible(title, identifier: identifier, in: app) {
      return
    }
    // Downwards first: callers walk a screen top to bottom, so the target is
    // almost always below wherever the last lookup stopped.
    for _ in 0..<Self.crownScrollSpan {
      XCUIDevice.shared.rotateDigitalCrown(delta: Self.crownScrollStep)
      if isVisible(title, identifier: identifier, in: app) {
        return
      }
    }
    // Not below, so it is above: rewind and come down the whole list once.
    // One big turn rather than several small ones — the top is a hard stop,
    // so there is nothing to overshoot into.
    XCUIDevice.shared.rotateDigitalCrown(
      delta: -Self.crownScrollStep * Double(Self.crownScrollSpan + 1)
    )
    for _ in 0..<Self.crownScrollSpan {
      if isVisible(title, identifier: identifier, in: app) {
        return
      }
      XCUIDevice.shared.rotateDigitalCrown(delta: Self.crownScrollStep)
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
