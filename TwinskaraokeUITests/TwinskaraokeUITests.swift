import XCTest
#if canImport(UIKit)
  import UIKit
#endif

@MainActor
final class TwinskaraokeUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testThresholdTabReveal() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1", "-UITestNativeTabReveal", "-UITestThresholdTabReveal"]
    app.launch()
    let scroll = app.scrollViews["NativeReveal.Scroll"]
    let placement = app.staticTexts["NativeReveal.Placement"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    for _ in 0..<4 { scroll.swipeUp() }
    XCTAssertTrue(waitUntil(timeout: 5) { placement.label == "inline" })
    let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)),
                withVelocity: 250, thenHoldForDuration: 0)
    XCTAssertTrue(waitUntil(timeout: 5) { placement.label == "expanded" })
    XCTAssertTrue(waitUntil(timeout: 5) {
      app.staticTexts["NativeReveal.Offset"].value as? String == "native"
    }, "The reveal must finish and restore native scrolling before the next cycle.")
    // How many downward swipes it takes to minimize again *after* a reveal.
    // One is enough on iOS 26. If iOS 27 needs more, that is a reveal-distance
    // difference and the feature still works; if no number works, the reveal
    // has left the bar unable to minimize at all, which is a functional break
    // rather than the cosmetic one this was chased as. Report which.
    var swipes = 0
    for attempt in 1...4 {
      scroll.swipeUp()
      swipes = attempt
      if waitUntil(timeout: 2, { placement.label == "inline" }) { break }
    }
    XCTAssertEqual(
      placement.label, "inline",
      "The tab bar never minimized again after a reveal, across \(swipes) swipes."
    )
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)),
                withVelocity: 250, thenHoldForDuration: 0)
    XCTAssertTrue(waitUntil(timeout: 5) { placement.label == "expanded" },
                  "The second reveal did not expand after \(swipes) swipes to minimize.")
  }

  /// What gesture does UIKit's own restore actually want?
  ///
  /// `TabBarMinimizeBehavior` documents `.onScrollDown` as minimizing the bar
  /// "as soon as someone scrolls down through a feed, and restores it when they
  /// scroll back up", while IOS27_TESTER_FEEDBACK.md records the native reveal
  /// firing "only at the top of the scroll view". Neither says what counts as
  /// scrolling back up, and that is the whole question: if a plain flick
  /// restores the bar away from the scroll edge, the short reveal needs no
  /// policy flipping at all and none of its animation problems come with it.
  ///
  /// Escalating gestures, no flip installed, nothing of this app around the tab
  /// bar, starting far from the top. Prints the table either way.
  func testNativeRevealOnScrollUp() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1", "-UITestNativeTabReveal", "-UITestNativeRevealOnly"]
    app.launch()
    let scroll = app.scrollViews["NativeReveal.Scroll"]
    let placement = app.staticTexts["NativeReveal.Placement"]
    let offsetText = app.staticTexts["NativeReveal.Offset"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    for _ in 0..<4 { scroll.swipeUp() }
    XCTAssertTrue(waitUntil(timeout: 5) { placement.label == "inline" },
                  "The bar never minimized, so there is nothing to restore.")
    XCTAssertGreaterThan(scrollOffset(offsetText), 400,
                         "Must be well away from the scroll edge for this to mean anything.")

    let origin = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    func reverse(_ points: CGFloat, velocity: XCUIGestureVelocity) {
      origin.press(forDuration: 0.05,
                   thenDragTo: origin.withOffset(CGVector(dx: 0, dy: points)),
                   withVelocity: velocity, thenHoldForDuration: 0)
    }

    // Each attempt starts minimized; re-minimize between them so one attempt
    // cannot inherit another's restore.
    let attempts: [(String, () -> Void)] = [
      ("160pt slow drag", { reverse(160, velocity: 250) }),
      ("160pt flick", { reverse(160, velocity: 2500) }),
      ("400pt drag", { reverse(400, velocity: 800) }),
      ("full swipeDown flick", { scroll.swipeDown() }),
    ]

    var rows: [String] = []
    var restoredBy: String?
    for (name, gesture) in attempts {
      guard waitUntil(timeout: 3, { placement.label == "inline" }) else {
        rows.append("\(name): skipped, bar was not minimized beforehand")
        continue
      }
      let before = scrollOffset(offsetText)
      gesture()
      let restored = waitUntil(timeout: 3) { placement.label == "expanded" }
      let after = scrollOffset(offsetText)
      rows.append("\(name): restored=\(restored) offset \(before) -> \(after)")
      if restored, restoredBy == nil, after > 200 { restoredBy = name }
      if restored { for _ in 0..<3 { scroll.swipeUp() } }
    }

    let table = "native restore characterisation\n" + rows.joined(separator: "\n")
    print(table)
    let attachment = XCTAttachment(string: table)
    attachment.lifetime = .keepAlways
    add(attachment)

    // Recorded, not asserted: whether a reversal short of the scroll edge
    // restores the bar is the thing being measured, and on iOS 26.5 the answer
    // is no for every gesture tried — only the flick that reached offset 0 did.
    // Asserting the documented behaviour would pin the suite red against the OS.
    // What is worth guarding is that the edge restore works at all.
    XCTAssertTrue(
      rows.contains { $0.hasPrefix("full swipeDown flick") && $0.contains("restored=true") },
      "Even reaching the scroll edge no longer restores the tab bar.\n\(table)"
    )
    if restoredBy == nil {
      print("native restore is scroll-edge-only on this OS; a short reveal needs the policy flip")
    }
  }

  func testNativeTabRevealDiagnostic() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1", "-UITestNativeTabReveal"]
    app.launch()
    let scroll = app.scrollViews["NativeReveal.Scroll"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    func record(_ stage: String) {
      let placement = app.staticTexts["NativeReveal.Placement"].label
      let offset = app.staticTexts["NativeReveal.Offset"].label
      let note = "Native reveal \(stage): offset=\(offset), placement=\(placement)"
      print(note)
      let attachment = XCTAttachment(string: note)
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    record("initial")
    for _ in 0..<5 { scroll.swipeUp() }
    record("scrolled down")
    let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 140)),
                withVelocity: 250, thenHoldForDuration: 0)
    record("140-point reverse")
    scroll.swipeDown()
    record("long reverse")
    // Diagnostic only: record native policy rather than asserting an
    // undocumented threshold. The offset proves whether we reached the top.
    XCTAssertTrue(scroll.exists)
  }

  func testAppLaunches() throws {
    let app = launchApp()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
  }

  func testRootNavigationShowsCoreMusicSections() throws {
    let app = launchApp()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    for section in ["Home", "New", "Radio", "Library", "Search"] {
      openRootSection(section, in: app)
      XCTAssertTrue(
        app.navigationBars[section].waitForExistence(timeout: 8)
          || app.staticTexts[section].waitForExistence(timeout: 8),
        "Expected \(section) to be visible after selecting the root section."
      )
    }
  }

  func testLibraryAndSearchDrillDownNavigation() throws {
    let libraryApp = launchApp(initialSection: "library")
    XCTAssertTrue(libraryApp.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      libraryApp.staticTexts["Artists"].waitForExistence(timeout: 8),
      "Expected Library primary links to be visible."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Library.WideOverview", in: libraryApp, timeout: 8),
        "Expected Library to use a wide overview layout on iPad."
      )
    }
    openVisibleItem("Artists", in: libraryApp)
    XCTAssertTrue(
      libraryApp.navigationBars["Artists"].waitForExistence(timeout: 8)
        || libraryApp.staticTexts["Artists"].waitForExistence(timeout: 8),
      "Expected Artists library destination to be visible."
    )
    libraryApp.terminate()

    let searchApp = launchApp(initialSection: "search")
    XCTAssertTrue(searchApp.wait(for: .runningForeground, timeout: 15))
    XCTAssertTrue(
      searchApp.staticTexts["Featured"].waitForExistence(timeout: 8),
      "Expected Search to expose featured Apple Music-style shortcuts."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(
          identifier: "SearchBrowse.WideHighlights",
          in: searchApp,
          timeout: 8
        ),
        "Expected Search to group featured shortcuts in a wide iPad layout."
      )
    }
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "SearchCategory.TwinskaraokeTop100",
        in: searchApp,
        timeout: 8
      ),
      "Expected Search to expose the Top 100 browse shortcut."
    )
    openVisibleItem(
      "Twinskaraoke Top 100",
      identifier: "SearchCategory.TwinskaraokeTop100",
      in: searchApp
    )
    XCTAssertTrue(
      searchApp.staticTexts["Twinskaraoke Top 100"].waitForExistence(timeout: 8)
        || searchApp.navigationBars["Twinskaraoke Top 100"].waitForExistence(timeout: 8),
      "Expected Top 100 shortcut to open its collection."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "BrowseSongCollection.WideOverview", in: searchApp, timeout: 8),
        "Expected song collections to use a wide Apple Music-style overview on iPad."
      )
    }
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "BrowseSongCollection.song.ui-top-song-1",
      in: searchApp
    )
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "BrowseSongCollection.song.ui-top-song-1",
        in: searchApp,
        timeout: 8
      )
        || searchApp.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected Top 100 to show fixture songs in UI test mode."
    )
    searchApp.navigationBars.buttons.element(boundBy: 0).tap()

    openVisibleItem("Dance", in: searchApp)
    XCTAssertTrue(
      searchApp.navigationBars["Dance"].waitForExistence(timeout: 8)
        || searchApp.staticTexts["Dance"].waitForExistence(timeout: 8),
      "Expected Dance browse category to be visible."
    )
  }

  func testSearchPublicPlaylistsShortcutOpensPlaylistDetail() throws {
    let app = launchApp(initialSection: "search")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      accessibleElementExists(
        identifier: "SearchCategory.PublicPlaylists",
        in: app,
        timeout: 8
      ),
      "Expected Search to expose the Public Playlists browse shortcut."
    )
    openVisibleItem(
      "Public Playlists",
      identifier: "SearchCategory.PublicPlaylists",
      in: app
    )

    XCTAssertTrue(
      app.navigationBars["Public Playlists"].waitForExistence(timeout: 8)
        || app.staticTexts["Public Playlists"].waitForExistence(timeout: 8),
      "Expected Public Playlists shortcut to open its collection."
    )
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "PlaylistList.ui-search-playlist-essentials",
        in: app,
        timeout: 8
      )
        || app.staticTexts["Karaoke Essentials"].waitForExistence(timeout: 8),
      "Expected fixture public playlists to be visible in UI test mode."
    )

    openVisibleItem(
      "Karaoke Essentials",
      identifier: "PlaylistList.ui-search-playlist-essentials",
      in: app
    )
    XCTAssertTrue(
      app.staticTexts["Karaoke Essentials"].waitForExistence(timeout: 8)
        || app.navigationBars["Karaoke Essentials"].waitForExistence(timeout: 8),
      "Expected tapping a public playlist to open playlist details."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        playlistDetailUsesWideOverview(in: app, timeout: 8),
        "Expected playlist detail to use a wide Apple Music-style overview on iPad."
      )
    }
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "PlaylistDetail.song.0.ui-search-song-1",
      in: app
    )
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "PlaylistDetail.song.0.ui-search-song-1",
        in: app,
        timeout: 8
      )
        || app.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected playlist detail to show fixture songs."
    )
  }

  func testOpeningPlaylistDoesNotAddItToRecentlyPlayed() throws {
    let app = launchApp(initialSection: "search", resetRecentlyPlayed: true)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem("Public Playlists", identifier: "SearchCategory.PublicPlaylists", in: app)
    openVisibleItem(
      "Karaoke Essentials",
      identifier: "PlaylistList.ui-search-playlist-essentials",
      in: app
    )
    XCTAssertTrue(
      app.staticTexts["Karaoke Essentials"].waitForExistence(timeout: 8)
        || app.navigationBars["Karaoke Essentials"].waitForExistence(timeout: 8),
      "Expected the playlist detail to open before checking playback history."
    )

    openRootSection("Home", in: app)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    XCTAssertFalse(
      accessibleElementExists(identifier: "Home.RecentlyPlayed", in: app, timeout: 2),
      "Opening a playlist without playing from it must not add it to Recently Played."
    )

    openRootSection("Search", in: app)
    let firstSongIdentifier = "PlaylistDetail.song.0.ui-search-song-1"
    let firstSong = element(identifier: firstSongIdentifier, in: app)
    if !waitUntil(timeout: 2, { firstSong.isHittable }) {
      // A split-view section switch may restore Search at its root instead of
      // preserving the pushed playlist. Reopen it explicitly so this test
      // measures history semantics, not NavigationSplitView path retention.
      openVisibleItem("Public Playlists", identifier: "SearchCategory.PublicPlaylists", in: app)
      openVisibleItem(
        "Karaoke Essentials",
        identifier: "PlaylistList.ui-search-playlist-essentials",
        in: app
      )
    }
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: firstSongIdentifier,
      in: app
    )
    XCTAssertTrue(
      waitUntil(timeout: 5) { firstSong.isHittable && self.tapStartsPlayback(firstSong, in: app) },
      "Expected deliberate playlist playback to start."
    )

    openRootSection("Home", in: app)
    XCTAssertTrue(
      accessibleElementExists(identifier: "Home.RecentlyPlayed", in: app, timeout: 5),
      "Playing from the playlist must add it to Recently Played."
    )
  }

  /// Swiping a zoom-pushed screen away must not start playback.
  ///
  /// Two ways it did, both measured on iOS 26.5 before `ZoomPushDismissal`
  /// disabled `_UIContentSwipeDismissGestureRecognizer`: the outgoing screen kept
  /// hit testing for the ~0.9s the interactive dismissal ran, so a tap aimed at
  /// the list behind it landed on a song row; and once that recogniser was gone,
  /// a sideways drag over a row was delivered as a plain tap on the row.
  func testSwipingBackFromPlaylistDetailStartsNoPlayback() throws {
    let app = launchApp(initialSection: "search")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem("Public Playlists", identifier: "SearchCategory.PublicPlaylists", in: app)
    XCTAssertTrue(app.staticTexts["Karaoke Essentials"].waitForExistence(timeout: 8))

    let tile = element(identifier: "PlaylistList.ui-search-playlist-essentials", in: app)
    XCTAssertTrue(tile.waitForExistence(timeout: 8))
    tile.tap()
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "PlaylistDetail.song.0.ui-search-song-1",
      in: app
    )
    let songRow = element(identifier: "PlaylistDetail.song.0.ui-search-song-1", in: app)
    XCTAssertTrue(
      songRow.waitForExistence(timeout: 8),
      "Expected a song row on screen, so the swipe below crosses one."
    )

    // Deliberately across the song row rather than along the leading edge: the
    // gesture this replaces was never edge-limited.
    let swipeY = songRow.frame.midY
    let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
    origin.withOffset(CGVector(dx: 34, dy: swipeY)).press(
      forDuration: 0.05,
      thenDragTo: origin.withOffset(CGVector(dx: 170, dy: swipeY + 5)),
      withVelocity: 250,
      thenHoldForDuration: 0
    )

    // Immediately, while the screen is still shrinking, and at the row's own Y:
    // that is where the outgoing screen used to claim the touch. Once it is gone
    // the same point is the playlist list, where a tap opens a playlist and
    // starts nothing.
    origin.withOffset(CGVector(dx: 200, dy: swipeY)).tap()

    XCTAssertFalse(
      waitUntil(timeout: 3) { self.miniPlayerExists(in: app) },
      "Neither the swipe nor a tap during the shrink may start playback."
    )

    // Keeps the assertion above honest: a deliberate tap on a row still plays,
    // so its absence means the swipe was ignored rather than playback being
    // unobservable here. Relaunched because the tap above may have opened a
    // playlist of its own.
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem("Public Playlists", identifier: "SearchCategory.PublicPlaylists", in: app)
    openVisibleItem(
      "Karaoke Essentials",
      identifier: "PlaylistList.ui-search-playlist-essentials",
      in: app
    )
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "PlaylistDetail.song.0.ui-search-song-1",
      in: app
    )
    let firstSong = element(identifier: "PlaylistDetail.song.0.ui-search-song-1", in: app)
    XCTAssertTrue(firstSong.waitForExistence(timeout: 8))
    // The arriving screen holds playback taps back until the zoom finishes.
    XCTAssertTrue(
      waitUntil(timeout: 5) { firstSong.isHittable && self.tapStartsPlayback(firstSong, in: app) },
      "A deliberate tap on a song row must start playback."
    )
  }

  /// Taps and reports whether the mini player showed up, so the caller can retry
  /// while the screen is still arriving.
  private func tapStartsPlayback(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    element.tap()
    return waitUntil(timeout: 1.5) { self.miniPlayerExists(in: app) }
  }

  /// Whether the mini player is on screen, under either element type.
  ///
  /// It resolves as a *button*: it carries a button trait, because tapping it
  /// opens the player. It was an `other` element while the bar was a plain
  /// `UIView` supplied by LNPopupUI. Both are checked rather than just the one
  /// that happens to be current, because the assertions above are negative —
  /// querying only the type the bar no longer uses would make "the mini player
  /// did not appear" pass without the mini player having anything to do with it.
  private func miniPlayerExists(in app: XCUIApplication) -> Bool {
    app.buttons["MiniPlayerBar"].firstMatch.exists
      || app.otherElements["MiniPlayerBar"].firstMatch.exists
  }

  /// Present *and* reachable. The full player covers the window while it is
  /// presenting, so this is what says it has really gone.
  private func miniPlayerIsHittable(in app: XCUIApplication) -> Bool {
    app.buttons["MiniPlayerBar"].firstMatch.isHittable
      || app.otherElements["MiniPlayerBar"].firstMatch.isHittable
  }

  /// The probe's offset readout, ignoring the locale's grouping separator.
  private func scrollOffset(_ element: XCUIElement) -> Int {
    Int(element.label.filter { $0.isNumber || $0 == "-" }) ?? 0
  }

  private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  /// The playlist actions must have a home of their own in the toolbar.
  ///
  /// They were lost with the navigation-bar block when pull-to-reveal search
  /// replaced the old search field, leaving `PlaylistMoreMenu` defined but
  /// unreferenced — which no compiler warning catches for a private type.
  func testPlaylistDetailToolbarExposesPlaylistActions() throws {
    let app = launchApp(initialSection: "search")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openVisibleItem("Public Playlists", identifier: "SearchCategory.PublicPlaylists", in: app)
    openVisibleItem(
      "Karaoke Essentials",
      identifier: "PlaylistList.ui-search-playlist-essentials",
      in: app
    )

    let moreActions = app.buttons["PlaylistDetail.moreActions"]
    XCTAssertTrue(
      moreActions.waitForExistence(timeout: 8),
      "Expected the playlist actions menu in the navigation bar."
    )
    moreActions.tap()

    // The download entry's title depends on what is already downloaded, and
    // "Add to Library" is absent for a playlist you own, so assert on the menu
    // having opened with the actions in it rather than on one exact title.
    XCTAssertTrue(
      app.buttons["Refresh Playlist"].waitForExistence(timeout: 5),
      "Expected the actions menu to open."
    )
    for title in ["Play", "Shuffle"] {
      XCTAssertTrue(app.buttons[title].exists, "Expected \(title) in the actions menu.")
    }
    // Three titles rather than one: which download action appears depends on
    // what the simulator already has on disk, and downloads outlive a launch.
    // The in-flight "Downloading n…" state is deliberately not among them —
    // nothing here starts a download, so accepting it would only have widened
    // what counts as a pass.
    XCTAssertTrue(
      app.buttons["Download"].exists
        || app.buttons["Download Remaining"].exists
        || app.buttons["Remove Downloads"].exists,
      "Expected a download action in the actions menu."
    )
  }

  func testAdaptiveMusicShellShowsSidebarOrTabs() throws {
    // In portrait the balanced split view collapses the sidebar out of the
    // hierarchy, so an iPad would fall through to the compact tab assertions
    // and fail. Landscape is what makes the sidebar branch deterministic.
    // Orientation is process-wide, so restore it rather than leaking landscape
    // into whichever test runs next.
    let originalOrientation = XCUIDevice.shared.orientation
    defer { XCUIDevice.shared.orientation = originalOrientation }
    if isRunningOnPad {
      XCUIDevice.shared.orientation = .landscapeLeft
    }

    let app = launchApp()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    if app.staticTexts["Discover"].waitForExistence(timeout: 5) {
      XCTAssertTrue(app.staticTexts["Twinskaraoke"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Collection"].waitForExistence(timeout: 5))

      for section in ["home", "new", "radio", "library", "search"] {
        XCTAssertTrue(
          rootSectionExists(identifier: "RootSection.\(section)", in: app),
          "Expected iPad sidebar root section \(section) to be visible."
        )
      }
      openRootSection("Search", in: app)
      // Only the detail column proves the sidebar row actually drove selection:
      // the sidebar itself always carries a "Search" static text, so matching on
      // that alone passes even when no row is selectable at all.
      XCTAssertTrue(
        app.navigationBars["Search"].waitForExistence(timeout: 8),
        "Expected Search to open from the Discover sidebar group."
      )
      return
    }

    for section in ["Home", "New", "Radio", "Library", "Search"] {
      XCTAssertTrue(
        app.tabBars.buttons[section].waitForExistence(timeout: 5),
        "Expected compact tab \(section) to be visible."
      )
    }
  }

  func testHomeShowsMusicSectionsInUITestMode() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Home"].waitForExistence(timeout: 8)
        || app.navigationBars["Home"].waitForExistence(timeout: 8),
      "Expected Home to be visible."
    )
    XCTAssertTrue(
      app.staticTexts["Top Picks for You"].waitForExistence(timeout: 8),
      "Expected Home to render top picks instead of remaining in loading state."
    )
    XCTAssertTrue(
      app.staticTexts["Made for You"].waitForExistence(timeout: 8),
      "Expected Home to render song recommendations."
    )
    XCTAssertTrue(
      app.staticTexts["Latest Single"].waitForExistence(timeout: 8),
      "Expected Home to render the latest single feature."
    )

    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Home.WideOverview", in: app, timeout: 8),
        "Expected Home to use a wide Apple Music-style overview on iPad."
      )
    }
  }

  func testNewShowsAppleMusicSectionsInUITestMode() throws {
    let app = launchApp(initialSection: "new")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["New"].waitForExistence(timeout: 8)
        || app.navigationBars["New"].waitForExistence(timeout: 8),
      "Expected New to be visible."
    )
    XCTAssertTrue(
      app.staticTexts["Up Next"].waitForExistence(timeout: 8),
      "Expected New to render the Up Next shelf."
    )
    XCTAssertTrue(
      app.staticTexts["Best New Songs"].waitForExistence(timeout: 8),
      "Expected New to render the Best New Songs preview."
    )
    XCTAssertTrue(
      app.staticTexts["More to Explore"].waitForExistence(timeout: 8),
      "Expected New to render exploration links."
    )

    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "New.WideOverview", in: app, timeout: 8),
        "Expected New to use a wide Apple Music-style overview on iPad."
      )
    }
  }

  func testRadioShowsAppleMusicSectionsInUITestMode() throws {
    let app = launchApp(initialSection: "radio")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    openRootSection("Radio", in: app)

    XCTAssertTrue(
      app.staticTexts["Radio"].waitForExistence(timeout: 8)
        || app.navigationBars["Radio"].waitForExistence(timeout: 8),
      "Expected Radio to be visible."
    )
    XCTAssertTrue(
      accessibleElementExists(identifier: "Radio.FeaturedEpisode.Label", in: app, timeout: 8)
        || app.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected Radio to render the featured live episode."
    )
    XCTAssertTrue(
      app.buttons["Up Next"].waitForExistence(timeout: 8),
      "Expected Radio to render the live schedule preview."
    )
    XCTAssertTrue(
      accessibleElementExists(identifier: "Radio.HistorySection", in: app, timeout: 8),
      "Expected Radio to render recently played songs."
    )

    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Radio.WideOverview", in: app, timeout: 8),
        "Expected Radio to use a wide overview layout on iPad."
      )
    }
  }

  /// Dragging the player down must dismiss it, and hand the screen back.
  ///
  /// This covers the gesture end to end — that a downward drag on the player's
  /// body reaches `NowPlayingOverlay`'s recogniser, settles, and releases hit
  /// testing so the app underneath is usable again. The *decision* it settles
  /// on lives in `PlayerDismissMetricsTests`, which is where the velocity
  /// projection that used to fail is actually covered.
  ///
  /// It deliberately does not flick. XCUITest does not deliver the intermediate
  /// touches of a fast synthesized drag, so the gesture never begins: measured,
  /// the player sat at `progress=1.0` throughout while the assertions passed
  /// anyway, because an open player covering the screen reads as not hittable
  /// just as a dismissed one does. A slow drag does arrive, which is why this
  /// commits on distance instead.
  ///
  /// Repeated, because a stuck presentation only shows on the second open.
  func testPlayerSwipeUpAndSleepTimer() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    let tabs = XCTAttachment(screenshot: app.screenshot())
    tabs.name = "Search tab layout"
    tabs.lifetime = .keepAlways
    add(tabs)
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )
    let mini = app.descendants(matching: .any)["MiniPlayerBar"].firstMatch
    XCTAssertTrue(mini.waitForExistence(timeout: 8))
    let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)
    let handle = app.buttons["PlayerDismissHandle"]
    XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })
    // Status-bar geometry varies across devices and OS releases, so this is
    // measured against the actual bar rather than an iPhone-specific 60pt
    // cutoff. The whole tap target has to clear it, not just its centre: the
    // handle is padded down by the top safe inset, which is never smaller than
    // the bar, so anything less means the player has drifted upward.
    let statusBar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
    XCTAssertTrue(statusBar.exists)
    XCTAssertTrue(waitUntil(timeout: 8) { handle.frame.minY >= statusBar.frame.maxY },
                  "Dismiss handle \(handle.frame) must clear status bar \(statusBar.frame).")
    // Accessibility conversion can report 43.99999999999999 for a 44pt frame.
    XCTAssertGreaterThanOrEqual(handle.frame.height + 0.001, 44)
    let playerShot = XCTAttachment(screenshot: app.screenshot())
    playerShot.name = "Full player safe area"
    playerShot.lifetime = .keepAlways
    add(playerShot)
    app.buttons["More"].firstMatch.tap()
    app.buttons["SleepTimerMenu"].firstMatch.tap()
    app.buttons["15 minutes"].firstMatch.tap()
    let status = app.buttons["SleepTimerStatus"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    handle.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { self.miniPlayerIsHittable(in: app) })
    openMiniPlayer(in: app)
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    status.tap()
    XCTAssertTrue(app.buttons["30 minutes"].waitForExistence(timeout: 5))
    for minutes in [15, 30, 45, 60] {
      XCTAssertTrue(app.buttons["\(minutes) minutes"].firstMatch.isHittable,
                    "Countdown presets must be directly available without a submenu.")
    }
    XCTAssertEqual(app.buttons.matching(identifier: "Cancel Sleep Timer").count, 1)
    app.buttons["30 minutes"].firstMatch.tap()
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    status.tap()
    XCTAssertTrue(app.buttons["Cancel Sleep Timer"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Cancel Sleep Timer"].firstMatch.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { !status.exists })
  }

  func testPlayerMovesBeforeFingerIsReleased() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home", "-UITestPlayerTracking"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app
    )
    let mini = app.buttons["MiniPlayerBar"].firstMatch
    XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
    let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
    let lifted = start.withOffset(CGVector(dx: 0, dy: -app.frame.height * 0.4))
    start.press(forDuration: 0.4, thenDragTo: lifted, withVelocity: 180, thenHoldForDuration: 1)
    let handle = app.buttons["PlayerDismissHandle"]
    XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })
    let probe = app.descendants(matching: .any)["PlayerTrackingProbe"].firstMatch
    let opened = try XCTUnwrap(probe.value as? String).split(separator: ",")
    guard opened.count == 6 else {
      XCTFail("The opening tracking probe must report six measurements.")
      return
    }
    XCTAssertGreaterThan(Int(opened[0]) ?? 0, 100,
                         "The player must visibly move while the opening finger is still down.")
    XCTAssertGreaterThan(Int(opened[2]) ?? 0, 5,
                         "Opening must traverse intermediate positions, not jump to the endpoint.")

    // Less than the commit threshold, with a hold to remove release velocity.
    // The player returns to expanded, leaving the probe accessible for inspection.
    let top = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    top.press(forDuration: 0.4, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 150)),
              withVelocity: 150, thenHoldForDuration: 1)
    XCTAssertTrue(waitUntil(timeout: 5) { handle.isHittable })
    let closed = try XCTUnwrap(probe.value as? String).split(separator: ",")
    guard closed.count == 6 else {
      XCTFail("The closing tracking probe must report six measurements.")
      return
    }
    XCTAssertGreaterThan(Int(closed[1]) ?? 0, 80,
                         "The player must visibly move while the closing finger is still down.")
    XCTAssertGreaterThan(Int(closed[3]) ?? 0, 5,
                         "Closing must traverse intermediate positions before release.")
  }

  func testPlayerArtworkSettlesIntoMiniPlayerAfterRelease() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home",
                           "-UITestPlayerTracking", "-UITestPlayerClosingArtwork"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    openVisibleItem("Wake Me Up Before You Go-Go",
                    identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app)
    let mini = app.buttons["MiniPlayerBar"].firstMatch
    XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
    mini.tap()
    let handle = app.buttons["PlayerDismissHandle"]
    XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })
    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)),
                withVelocity: 700, thenHoldForDuration: 0)
    XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
    mini.tap()
    XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable })
    let probe = app.descendants(matching: .any)["PlayerTrackingProbe"].firstMatch
    let measurements = try XCTUnwrap(probe.value as? String).split(separator: ",")
    guard measurements.count == 6 else {
      XCTFail("The landing tracking probe must report six measurements.")
      return
    }
    XCTAssertGreaterThan(Int(measurements[4]) ?? 0, 8,
                         "Closing must render intermediate settlement frames, not jump to the pill.")
    XCTAssertGreaterThan(Int(measurements[5]) ?? 0, 1,
                         "The rendered artwork should dip below its resting thumbnail position before settling.")
  }

  func testShortMiniPlayerFlicksAndDragsExpand() throws {
    try checkShortMiniPlayerGestures(competingGesture: false)
  }

  func testMiniPlayerOpensDespiteAncestorPressGesture() throws {
    try checkShortMiniPlayerGestures(competingGesture: true)
  }

  private func checkShortMiniPlayerGestures(competingGesture: Bool) throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home"]
    if competingGesture { app.launchArguments.append("-UITestPlayerGestureCompetition") }
    app.launch()
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    openVisibleItem("Wake Me Up Before You Go-Go",
                    identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app)
    let mini = app.buttons["MiniPlayerBar"].firstMatch
    let handle = app.buttons["PlayerDismissHandle"]
    for (distance, speed, hold, x, y) in [
      (40.0, 600.0, 0.0, 0.35, 0.5), (85.0, 100.0, 0.5, 0.35, 0.05),
      (40.0, 600.0, 0.0, 0.35, 0.95), (85.0, 100.0, 0.5, 0.05, 0.5),
      (40.0, 600.0, 0.0, 0.35, 0.05), (85.0, 100.0, 0.5, 0.35, 0.95)
    ] {
      XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
      let start = mini.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
      start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                  withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: hold)
      XCTAssertTrue(waitUntil(timeout: 8) { handle.isHittable },
                    "A deliberate short upward flick or drag should open the player.")
      handle.tap()
    }
  }

  func testHeldTinyMiniPlayerDragsDoNotExpand() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    openVisibleItem("Wake Me Up Before You Go-Go",
                    identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app)
    let mini = app.buttons["MiniPlayerBar"].firstMatch
    for distance in [6.0, 10.0, 18.0, 6.0, 10.0, 18.0] {
      XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
      let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
      start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                  withVelocity: 30, thenHoldForDuration: 0.8)
      XCTAssertTrue(waitUntil(timeout: 5) { mini.isHittable },
                    "A held \(distance)-point drag must return to the mini player, not maximize.")
      XCTAssertFalse(app.buttons["PlayerDismissHandle"].isHittable)
    }
    // A normal tap must still work after cancelled drags.
    mini.tap()
    XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["PlayerDismissHandle"].isHittable })
  }

  func testMiniPlayerTransportTapDoesNotExpand() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 8))
    openVisibleItem("Wake Me Up Before You Go-Go",
                    identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app)
    let mini = app.buttons["MiniPlayerBar"].firstMatch
    XCTAssertTrue(waitUntil(timeout: 8) { mini.isHittable })
    let play = mini.buttons.matching(NSPredicate(format: "label == 'Play' OR label == 'Pause'")).firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 5))
    play.tap()
    XCTAssertTrue(mini.isHittable)
    XCTAssertFalse(app.buttons["PlayerDismissHandle"].isHittable)
    // The same area must still support opening when the contact becomes a drag.
    let start = play.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)),
                withVelocity: 150, thenHoldForDuration: 0.5)
    XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["PlayerDismissHandle"].isHittable })
  }

  func testDraggingDownDismissesTheFullScreenPlayer() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Made for You"].waitForExistence(timeout: 8),
      "Expected Home song shelf to be visible."
    )
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )

    let player = app.otherElements["FullScreenPlayer"]

    for attempt in 1...3 {
      openMiniPlayer(in: app)
      XCTAssertTrue(
        waitUntil(timeout: 8) { player.isHittable },
        "Attempt \(attempt): the mini player did not open the full-screen player."
      )

      // Started below the grabber, so this is the drag itself rather than the
      // dismiss button, which never had the bug.
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
      start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)

      // The mini player becoming tappable again is the assertion that means
      // something: the overlay covers the whole window while it is presenting,
      // so nothing underneath can be touched until it has actually gone.
      XCTAssertTrue(
        waitUntil(timeout: 5) { self.miniPlayerIsHittable(in: app) },
        "Attempt \(attempt): dragging down left the player up, or holding the screen."
      )
    }
  }

  /// Dragging the player down from the artwork must not be mistaken for a tap
  /// on it.
  ///
  /// The artwork used to be a `Button`, and a SwiftUI button fires on touch-up
  /// whenever the touch is still inside its bounds — it has no notion of the
  /// finger having travelled. The artwork is the largest target on the player,
  /// so a downward drag that began and ended on it stayed in bounds and opened
  /// the full-screen cover art instead of dismissing the player. Drags long
  /// enough to leave the artwork behaved, which is why it only happened
  /// sometimes.
  ///
  /// The drag here is deliberately contained within the artwork, since that is
  /// the only shape of gesture that ever reproduced it.
  func testDraggingDownFromTheArtworkDoesNotOpenTheCoverArt() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Made for You"].waitForExistence(timeout: 8),
      "Expected Home song shelf to be visible."
    )
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )

    openMiniPlayer(in: app)
    let player = app.otherElements["FullScreenPlayer"]
    XCTAssertTrue(
      waitUntil(timeout: 8) { player.isHittable },
      "The mini player did not open the full-screen player."
    )

    let artwork = playerArtwork(in: app)
    XCTAssertTrue(artwork.waitForExistence(timeout: 8), "Missing the player artwork.")

    // Keep both ends inside the artwork: that is the exact gesture the former
    // Button misread as a tap.
    let start = artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
    let end = artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)

    XCTAssertFalse(
      coverArtViewer(in: app).waitForExistence(timeout: 3),
      "Dragging the player down from the artwork opened the cover art."
    )
    // Both halves, because either one alone can be satisfied by a broken
    // player: a gesture that swallowed the drag outright would open no cover
    // art and dismiss nothing, and pass the assertion above on its own.
    if isRunningOnPad {
      // The landscape bottom bar uses a 64pt thumbnail only ~90pt above the
      // screen edge. A contained drag cannot cross the player's 25% commit
      // threshold, so first assert that it correctly springs back rather than
      // silently treating a missing dismissal assertion as success.
      XCTAssertFalse(
        waitUntil(timeout: 1) { self.miniPlayerIsHittable(in: app) },
        "A short contained iPad artwork drag unexpectedly dismissed the player."
      )

      // Then prove the artwork drag did not leave the shared gesture state
      // stuck: a deliberate full-surface pull must still dismiss normally.
      let dismissStart = player.coordinate(
        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)
      )
      let dismissEnd = player.coordinate(
        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)
      )
      dismissStart.press(
        forDuration: 0.05,
        thenDragTo: dismissEnd,
        withVelocity: 400,
        thenHoldForDuration: 0.1
      )
      XCTAssertTrue(
        waitUntil(timeout: 5) { self.miniPlayerIsHittable(in: app) },
        "The iPad player could not dismiss after a contained artwork drag."
      )
    } else {
      XCTAssertTrue(
        waitUntil(timeout: 5) { self.miniPlayerIsHittable(in: app) },
        "Dragging down from the artwork did not dismiss the full-screen player."
      )
    }
  }

  /// The other half of the bargain: a deliberate tap must still open it.
  func testTappingTheArtworkOpensTheCoverArt() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Made for You"].waitForExistence(timeout: 8),
      "Expected Home song shelf to be visible."
    )
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )

    openMiniPlayer(in: app)
    let player = app.otherElements["FullScreenPlayer"]
    XCTAssertTrue(
      waitUntil(timeout: 8) { player.isHittable },
      "The mini player did not open the full-screen player."
    )

    let artwork = playerArtwork(in: app)
    XCTAssertTrue(artwork.waitForExistence(timeout: 8), "Missing the player artwork.")
    artwork.tap()

    XCTAssertTrue(
      coverArtViewer(in: app).waitForExistence(timeout: 8),
      "Tapping the artwork no longer opens the cover art."
    )
  }

  func testQueueBrowsingAndReordering() throws {
    try verifyQueueEditing()
  }

  func testQueueEditingWithAccessibilityText() throws {
    try verifyQueueEditing(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXL")
  }

  private func verifyQueueEditing(contentSizeCategory: String? = nil) throws {
    let app = launchApp(initialSection: "home", preferredContentSizeCategory: contentSizeCategory)
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )
    let mini = element(identifier: "MiniPlayerBar", in: app)
    XCTAssertTrue(mini.waitForExistence(timeout: 8))
    let start = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.1)
    let queueButton = app.buttons["PlayerToolbar.PlayingNext"].firstMatch
    let queueButtonReady = waitUntil(timeout: 8) { queueButton.isHittable }
    if !queueButtonReady {
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Queue opening failure"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Queue opening hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertTrue(queueButtonReady, "The player queue button never became tappable")
    queueButton.tap()

    let reorder = app.buttons["Queue.Reorder"]
    XCTAssertTrue(reorder.waitForExistence(timeout: 8))
    XCTAssertEqual(reorder.label, "Reorder")
    XCTAssertTrue(reorder.isHittable)
    if contentSizeCategory != nil {
      let list = element(identifier: "Queue.List", in: app)
      XCTAssertTrue(waitUntil(timeout: 5) { list.frame.height > 160 })
    }
    let browseShot = XCTAttachment(screenshot: app.screenshot())
    browseShot.name = contentSizeCategory == nil ? "Queue browsing" : "Queue accessibility text"
    browseShot.lifetime = .keepAlways
    add(browseShot)

    reorder.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { reorder.label == "Done" })
    reorder.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { reorder.label == "Reorder" })
    reorder.tap()
    app.buttons["Clear queue"].tap()
    XCTAssertTrue(app.staticTexts["No songs queued"].waitForExistence(timeout: 5))
    XCTAssertFalse(reorder.exists)
    XCTAssertFalse(app.buttons["Clear queue"].exists)
  }

  func testPlaybackSessionRestoresPausedAfterRelaunch() throws {
    let app = XCUIApplication()
    let arguments = ["-UITestMode", "1", "-UITestInitialSection", "home", "-UITestPlaybackSession"]
    app.launchArguments = arguments + ["-UITestResetPlaybackSession"]
    app.launch()
    openVisibleItem("Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1", in: app)
    openMiniPlayer(in: app)
    let slider = app.sliders["Playback position"]
    XCTAssertTrue(slider.waitForExistence(timeout: 8))
    slider.adjust(toNormalizedSliderPosition: 0.4)
    XCUIDevice.shared.press(.home)
    app.terminate()
    app.launchArguments = arguments
    app.launch()
    XCTAssertTrue(app.buttons["MiniPlayerBar"].waitForExistence(timeout: 8),
      "The previous song must return without selecting it again.")
    openMiniPlayer(in: app)
    let restored = app.sliders["Playback position"]
    XCTAssertTrue(restored.waitForExistence(timeout: 8))
    XCTAssertTrue(waitUntil(timeout: 5) {
      let value = restored.value as? String ?? ""
      return value.contains("elapsed") && !value.hasPrefix("0:00")
    }, "The saved playback position must survive relaunch.")
    XCTAssertTrue(app.buttons["Play"].exists, "Restoration must not automatically start audio.")
  }

  func testNativePlaybackSliderDoesNotDismissPlayer() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-UITestInitialSection", "home", "-UITestScrubTracking"]
    app.launch()
    defer {
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Player hierarchy after native scrubbing"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Native player controls"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )
    openMiniPlayer(in: app)
    let slider = app.sliders["Playback position"]
    XCTAssertTrue(slider.waitForExistence(timeout: 8))
    XCTAssertTrue(slider.isEnabled)
    let probe = app.descendants(matching: .any)["NativeScrubValueProbe"].firstMatch
    func reached(_ target: Double) -> Bool {
      guard let text = probe.value as? String, let value = Double(text) else { return false }
      return abs(value - target) < 0.08
    }
    slider.adjust(toNormalizedSliderPosition: 0.6)
    XCTAssertTrue(waitUntil(timeout: 5) { reached(0.6) }, "First scrub must update the bound progress.")
    // iOS 27 reports this thumb-free slider as non-hittable after adjustment,
    // despite the visible track. Verify continued interaction with a real drag.
    slider.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
      .press(forDuration: 0.15, thenDragTo:
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55)))
    XCTAssertTrue(waitUntil(timeout: 5) { reached(0.25) }, "A second scrub must still change progress.")
    let queueButton = app.buttons["PlayerToolbar.PlayingNext"]
    XCTAssertTrue(queueButton.exists, "Scrubbing must leave the player open.")
    // Use the visible control's center rather than XCTest's hit-point estimate,
    // then prove that the app handled the touch by observing the queue sheet.
    queueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Queue.Reorder"].waitForExistence(timeout: 8),
                  "Playing Next must still open the queue after repeated scrubbing.")
  }

  func testHomeSongOpensFullScreenPlayerControls() throws {
    let app = launchApp(initialSection: "home")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Made for You"].waitForExistence(timeout: 8),
      "Expected Home song shelf to be visible."
    )
    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )
    openMiniPlayer(in: app)

    XCTAssertTrue(
      app.buttons["Play"].waitForExistence(timeout: 8)
        || app.buttons["Pause"].waitForExistence(timeout: 8),
      "Expected the full-screen player to expose the primary playback control."
    )
    XCTAssertTrue(
      app.buttons["Playing Next"].waitForExistence(timeout: 8),
      "Expected the full-screen player to expose the queue control."
    )
    XCTAssertTrue(
      app.staticTexts["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8)
        || app.buttons["Wake Me Up Before You Go-Go"].waitForExistence(timeout: 8),
      "Expected the selected song title to be visible in the player."
    )

    // The lyrics-first default follows the canvas, not the device idiom: an
    // iPad Slide Over or half-width Split View window runs the compact layout
    // and opens on artwork, so gate on the dedicated lyrics column actually
    // being present rather than on the device being an iPad. The column's title
    // is unique to the wide lyrics layout, and unlike its enclosing
    // `FullScreenPlayer.layout.wideLyrics` container it is queryable here.
    if accessibleElementExists(
      identifier: "FullScreenPlayer.wideLyricsTitle",
      in: app,
      timeout: 8
    ) {
      // The wide canvas opens straight into lyrics, so the toggle starts "on".
      XCTAssertTrue(
        app.buttons["Hide Lyrics"].waitForExistence(timeout: 8),
        "Expected the wide player to open with lyrics already showing."
      )

      app.buttons["Hide Lyrics"].firstMatch.tap()
      XCTAssertTrue(
        app.buttons["Show Lyrics"].waitForExistence(timeout: 8),
        "Expected the wide player to fall back to the artwork layout."
      )
      app.buttons["Show Lyrics"].firstMatch.tap()
      XCTAssertTrue(
        app.buttons["Hide Lyrics"].waitForExistence(timeout: 8),
        "Expected the wide player to return to lyrics mode."
      )
    } else {
      let lyricsButton = app.buttons["Show Lyrics"].firstMatch
      XCTAssertTrue(
        lyricsButton.waitForExistence(timeout: 8),
        "Expected the full-screen player to expose lyrics controls."
      )
      lyricsButton.tap()

      XCTAssertTrue(
        app.buttons["Hide Lyrics"].waitForExistence(timeout: 8)
          || app.buttons["Hide lyrics"].waitForExistence(timeout: 8),
        "Expected the player to switch into lyrics mode."
      )
    }
  }

  func testAccessibilityDynamicTypeKeepsPlayerControlsReachable() throws {
    let app = launchApp(
      initialSection: "home",
      preferredContentSizeCategory: "UICTContentSizeCategoryAccessibilityXL"
    )
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    openVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "HomeSongSection.Made for You.ui-home-song-1",
      in: app
    )
    openMiniPlayer(in: app)

    XCTAssertTrue(
      waitUntil(timeout: 8) {
        app.buttons["Play"].firstMatch.isHittable
          || app.buttons["Pause"].firstMatch.isHittable
      },
      "The primary transport control disappeared at an accessibility text size."
    )
    XCTAssertTrue(
      waitUntil(timeout: 8) { app.buttons["Playing Next"].firstMatch.isHittable },
      "The queue control disappeared at an accessibility text size."
    )
    XCTAssertTrue(
      waitUntil(timeout: 8) {
        app.buttons["Show Lyrics"].firstMatch.isHittable
          || app.buttons["Hide Lyrics"].firstMatch.isHittable
      },
      "The lyrics control disappeared at an accessibility text size."
    )
  }

  func testAccountToolbarOpensAccountAndSettings() throws {
    let app = launchApp()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    openAccountToolbar(in: app)
    XCTAssertTrue(
      app.navigationBars["Account"].waitForExistence(timeout: 8)
        || app.staticTexts["Account"].waitForExistence(timeout: 8),
      "Expected Account to open from the profile toolbar button."
    )

    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Account.WideOverview", in: app, timeout: 8),
        "Expected Account to use the centered regular-width overview on iPad."
      )
    }

    openVisibleItem("Settings", in: app)
    XCTAssertTrue(
      app.navigationBars["Music"].waitForExistence(timeout: 8)
        || app.staticTexts["Music"].waitForExistence(timeout: 8),
      "Expected Settings to open from Account."
    )

    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Settings.WideOverview", in: app, timeout: 8),
        "Expected Settings to use the centered regular-width overview on iPad."
      )
    }
  }

  func testSettingsPersistAutoplayAndEnforceTransitionChoice() throws {
    let app = launchApp()
    openAccountToolbar(in: app)
    openVisibleItem("Settings", in: app)
    let autoplay = app.switches["Autoplay"].firstMatch
    let autoMix = app.switches["Auto Mix"].firstMatch
    let crossfade = app.switches["Crossfade"].firstMatch
    XCTAssertTrue(autoplay.waitForExistence(timeout: 8))
    let originalAutoplay = autoplay.value as? String
    let originalAutoMix = autoMix.value as? String
    let originalCrossfade = crossfade.value as? String
    defer {
      if autoplay.exists, autoplay.value as? String != originalAutoplay { autoplay.tap() }
      if autoMix.exists, autoMix.value as? String != originalAutoMix { autoMix.tap() }
      if crossfade.exists, crossfade.value as? String != originalCrossfade { crossfade.tap() }
    }

    if autoMix.value as? String != "1" {
      autoMix.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
    XCTAssertEqual(crossfade.value as? String, "0")
    crossfade.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    XCTAssertEqual(crossfade.value as? String, "1")
    XCTAssertEqual(autoMix.value as? String, "0")
    XCTAssertTrue(app.sliders["Crossfade Duration"].waitForExistence(timeout: 3))

    autoplay.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let selectedAutoplay = autoplay.value as? String
    XCTAssertNotEqual(selectedAutoplay, originalAutoplay)
    app.terminate()
    app.launch()
    openAccountToolbar(in: app)
    openVisibleItem("Settings", in: app)
    XCTAssertTrue(autoplay.waitForExistence(timeout: 8))
    XCTAssertEqual(autoplay.value as? String, selectedAutoplay)
  }

  func testSettingsUseSelectedLanguageForThemeAndStrength() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode", "1", "-nk.language", "de", "-nk.appearance", "light",
                           "-nk.hapticsEnabled", "YES", "-nk.hapticStrength", "medium"]
    app.launch()
    defer { app.terminate() }
    openAccountToolbar(in: app)
    openVisibleItem("Einstellungen", in: app)
    XCTAssertTrue(app.switches["Automatische Wiedergabe"].waitForExistence(timeout: 8))
    let theme = app.descendants(matching: .any).matching(identifier: "Settings.Theme").firstMatch
    for _ in 0..<7 {
      if theme.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(theme.isHittable)
    // The theme and strength labels come from runtime values rather than
    // literal Text calls; verify they use the chosen locale too.
    XCTAssertTrue(theme.label.contains("Hell"), theme.debugDescription)
    let strength = app.descendants(matching: .any).matching(identifier: "Settings.HapticStrength").firstMatch
    XCTAssertTrue(strength.label.contains("Mittel"), strength.debugDescription)
  }

  func testAccountInformationDestinationsUseAdaptiveLayouts() throws {
    let app = launchApp()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    openAccountToolbar(in: app)
    XCTAssertTrue(
      app.navigationBars["Account"].waitForExistence(timeout: 8)
        || app.staticTexts["Account"].waitForExistence(timeout: 8),
      "Expected Account to open from the profile toolbar button."
    )

    openVisibleItem("Notifications", in: app)
    XCTAssertTrue(
      app.navigationBars["Notifications"].waitForExistence(timeout: 8)
        || app.staticTexts["Notifications"].waitForExistence(timeout: 8),
      "Expected Notifications to open from Account."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Notifications.WideOverview", in: app, timeout: 8),
        "Expected Notifications to use the centered regular-width overview on iPad."
      )
    }

    navigateBack(in: app)
    openVisibleItem("About", in: app)
    XCTAssertTrue(
      app.navigationBars["About"].waitForExistence(timeout: 8)
        || app.staticTexts["About"].waitForExistence(timeout: 8),
      "Expected About to open from Account."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "About.WideOverview", in: app, timeout: 8),
        "Expected About to use the centered regular-width overview on iPad."
      )
    }

    openVisibleItem("Credits", in: app)
    XCTAssertTrue(
      app.navigationBars["Credits"].waitForExistence(timeout: 8)
        || app.staticTexts["Credits"].waitForExistence(timeout: 8),
      "Expected Credits to open from About."
    )
    if isRunningOnPad {
      XCTAssertTrue(
        accessibleElementExists(identifier: "Credits.WideOverview", in: app, timeout: 8),
        "Expected Credits to use the centered regular-width overview on iPad."
      )
    }
  }

  func testLibraryToolbarShowsPlaylistActions() throws {
    let app = launchApp(initialSection: "library")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Library"].waitForExistence(timeout: 8)
        || app.navigationBars["Library"].waitForExistence(timeout: 8),
      "Expected Library to be visible."
    )

    if app.buttons["More Library Actions"].waitForExistence(timeout: 5) {
      app.buttons["More Library Actions"].tap()
      XCTAssertTrue(
        app.buttons["New Playlist"].waitForExistence(timeout: 5)
          || app.staticTexts["New Playlist"].waitForExistence(timeout: 5),
        "Expected Library actions menu to contain New Playlist."
      )
      return
    }

    XCTAssertTrue(
      app.buttons["New Playlist"].waitForExistence(timeout: 5),
      "Expected expanded Library toolbar to expose New Playlist."
    )
  }

  private func launchApp(
    initialSection: String? = nil,
    resetRecentlyPlayed: Bool = false,
    preferredContentSizeCategory: String? = nil
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
    if resetRecentlyPlayed {
      app.launchArguments.append("-UITestResetRecentlyPlayed")
    }
    if let initialSection {
      app.launchArguments += ["-UITestInitialSection", initialSection]
    }
    if let preferredContentSizeCategory {
      app.launchArguments += [
        "-UIPreferredContentSizeCategoryName",
        preferredContentSizeCategory,
      ]
    }
    app.launch()
    return app
  }

  private func openRootSection(_ title: String, in app: XCUIApplication) {
    let tabButton = app.tabBars.buttons[title].firstMatch
    if tabButton.waitForExistence(timeout: 3) {
      tabButton.tap()
      return
    }

    let identifier = "RootSection.\(title.lowercased())"
    let identifiedSidebarCell = app.cells.containing(.staticText, identifier: identifier).firstMatch
    if identifiedSidebarCell.waitForExistence(timeout: 3) {
      identifiedSidebarCell.tap()
      return
    }

    if app.staticTexts[identifier].waitForExistence(timeout: 3) {
      app.staticTexts[identifier].tap()
      return
    }

    if app.buttons[identifier].waitForExistence(timeout: 3) {
      app.buttons[identifier].tap()
      return
    }

    let identifiedCell = app.cells[identifier]
    if identifiedCell.waitForExistence(timeout: 3) {
      identifiedCell.tap()
      return
    }

    let sidebarCell = app.cells.containing(.staticText, identifier: title).firstMatch
    if sidebarCell.waitForExistence(timeout: 3) {
      sidebarCell.tap()
      return
    }

    let sidebarText = app.staticTexts.matching(identifier: title).element(boundBy: 0)
    if sidebarText.waitForExistence(timeout: 3) {
      sidebarText.tap()
      return
    }

    let fallbackButton = app.buttons[title].firstMatch
    if fallbackButton.waitForExistence(timeout: 3) {
      fallbackButton.tap()
      return
    }

    XCTAssertTrue(false, "Missing root navigation item \(title).")
  }

  private func openAccountToolbar(in app: XCUIApplication) {
    if app.buttons["AccountToolbarButton"].waitForExistence(timeout: 5) {
      app.buttons["AccountToolbarButton"].tap()
      return
    }

    if app.otherElements["AccountToolbarButton"].waitForExistence(timeout: 5) {
      app.otherElements["AccountToolbarButton"].tap()
      return
    }

    if app.buttons["Account"].waitForExistence(timeout: 5) {
      app.buttons["Account"].tap()
      return
    }

    XCTAssertTrue(false, "Missing account toolbar button.")
  }

  private func rootSectionExists(identifier: String, in app: XCUIApplication) -> Bool {
    accessibleElementExists(identifier: identifier, in: app, timeout: 2)
  }

  private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func openVisibleItem(_ title: String, identifier: String? = nil, in app: XCUIApplication) {
    if let identifier {
      if app.buttons[identifier].waitForExistence(timeout: 5) {
        app.buttons[identifier].tap()
        return
      }

      if app.otherElements[identifier].waitForExistence(timeout: 5) {
        app.otherElements[identifier].tap()
        return
      }

      if app.cells[identifier].waitForExistence(timeout: 5) {
        app.cells[identifier].tap()
        return
      }

      let identifiedElement = element(identifier: identifier, in: app)
      if identifiedElement.waitForExistence(timeout: 5) {
        identifiedElement.tap()
        return
      }
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

  private func navigateBack(in app: XCUIApplication) {
    let firstNavigationButton = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(firstNavigationButton.waitForExistence(timeout: 5), "Missing back navigation button.")
    firstNavigationButton.tap()
  }

  /// Matched on any element type: the artwork was a `Button` and is now a
  /// plain element carrying the button trait, and the identifier is the part
  /// that is meant to be stable across that.
  private func playerArtwork(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "PlayerArtwork").firstMatch
  }

  private func coverArtViewer(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "CoverArtViewer").firstMatch
  }

  private func openMiniPlayer(in app: XCUIApplication) {
    XCTAssertTrue(
      waitUntil(timeout: 8) { self.miniPlayerExists(in: app) },
      "Missing mini-player bar."
    )
    let miniPlayer =
      app.buttons["MiniPlayerBar"].firstMatch.exists
      ? app.buttons["MiniPlayerBar"].firstMatch
      : app.otherElements["MiniPlayerBar"].firstMatch
    // Hittable, not just present. Straight after a dismissal the full player is
    // still sliding down over the bar, and a tap sent then lands on the player
    // instead — which is why opening it a second time in a row failed.
    XCTAssertTrue(
      waitUntil(timeout: 8) { miniPlayer.isHittable },
      "Mini-player bar never became tappable."
    )
    miniPlayer.tap()
  }

  private func scrollToVisibleItem(_ title: String, identifier: String? = nil, in app: XCUIApplication) {
    for _ in 0..<6 {
      if let identifier {
        let identifiedElement = element(identifier: identifier, in: app)
        if identifiedElement.isHittable {
          return
        }
      }
      if app.staticTexts[title].firstMatch.isHittable
        || app.buttons[title].firstMatch.isHittable
      {
        return
      }
      app.swipeUp()
    }

    XCTAssertTrue(
      (identifier.map { element(identifier: $0, in: app).isHittable } ?? false)
        || app.staticTexts[title].firstMatch.isHittable
        || app.buttons[title].firstMatch.isHittable,
      "Missing visible item \(title) after scrolling."
    )
  }

  private func accessibleElementExists(
    identifier: String,
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    element(identifier: identifier, in: app).waitForExistence(timeout: timeout)
  }

  private func playlistDetailUsesWideOverview(
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    if accessibleElementExists(
      identifier: "PlaylistDetail.WideOverview",
      in: app,
      timeout: timeout
    ) {
      return true
    }

    // iOS 26 can omit identifier-only `.contain` accessibility containers.
    // Verify the actual two-column layout instead: the artwork/title rail must
    // sit meaningfully to the left of the first song column.
    let title = app.staticTexts["Karaoke Essentials"].firstMatch
    let firstSong = element(identifier: "PlaylistDetail.song.0.ui-search-song-1", in: app)
    guard title.waitForExistence(timeout: timeout),
          firstSong.waitForExistence(timeout: timeout)
    else { return false }
    return firstSong.frame.minX - title.frame.minX >= 280
  }

  private var isRunningOnPad: Bool {
    #if canImport(UIKit)
      return UIDevice.current.userInterfaceIdiom == .pad
    #else
      return false
    #endif
  }
}
