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

  // A "Listen Live starts and stays tuned in" test used to live here. It cost
  // roughly eleven minutes and could not earn them: a simulator streams over
  // the Mac's network with no media daemon to stall on, so it never reproduced
  // the main-actor freeze the off-actor tune-in was written to fix. The
  // behaviour it was reaching for has to be confirmed on a wrist.

  /// The Crown's volume mapping, pinned by direction rather than by arithmetic.
  ///
  /// Which way `digitalCrownRotation` counts is a platform fact, not something
  /// the source can be read for, and getting it backwards is invisible to every
  /// other test here. Forward — the direction that scrolls a list down, and the
  /// one `rotateDigitalCrown` calls positive — has to be the loud end.
  func testWatchPlayerCrownRolledForwardRaisesVolume() throws {
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

    // Volume starts at 100%, which parks the Crown against the top of its
    // range: it has to come down before a rise is measurable at all.
    XCUIDevice.shared.rotateDigitalCrown(delta: -0.6)
    let lowered = try crownVolumePercent(in: app)
    XCTAssertLessThan(lowered, 100, "Rolling the Crown backward should lower the volume.")

    XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
    let raised = try crownVolumePercent(in: app)
    XCTAssertGreaterThan(raised, lowered, "Rolling the Crown forward should raise the volume.")
  }

  /// Reads the Crown readout once it has stopped moving.
  ///
  /// The Crown keeps coasting after `rotateDigitalCrown` returns, so a reading
  /// taken straight afterwards can still be sliding. Sampling until two agree
  /// is what makes this test mean "where the Crown ended up" rather than
  /// "where it happened to be mid-glide".
  private func crownVolumePercent(in app: XCUIApplication) throws -> Int {
    let readout = app.descendants(matching: .any).matching(
      identifier: "WatchPlayer.crownReadout"
    ).firstMatch
    XCTAssertTrue(readout.waitForExistence(timeout: 5), "Missing the Crown readout.")

    // Four samples a third of a second apart. The turn itself already took
    // five seconds to return, so the value is usually settled on the first
    // read; this is the cheapest window that still catches one that isn't.
    var previous: Int?
    for _ in 0..<4 {
      let text = (readout.value as? String) ?? readout.label
      let percent = try XCTUnwrap(
        Int(text.filter(\.isNumber)), "Unreadable Crown volume: \(text)"
      )
      if percent == previous { return percent }
      previous = percent
      Thread.sleep(forTimeInterval: 0.3)
    }
    return try XCTUnwrap(previous)
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
