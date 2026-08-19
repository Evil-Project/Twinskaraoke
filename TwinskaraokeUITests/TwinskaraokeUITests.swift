import XCTest
#if canImport(UIKit)
  import UIKit
#endif

@MainActor
final class TwinskaraokeUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
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
        accessibleElementExists(identifier: "PlaylistDetail.WideOverview", in: app, timeout: 8),
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
    scrollToVisibleItem(
      "Wake Me Up Before You Go-Go",
      identifier: "PlaylistDetail.song.0.ui-search-song-1",
      in: app
    )
    let firstSong = element(identifier: "PlaylistDetail.song.0.ui-search-song-1", in: app)
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
      let start = player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
      let end = player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
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

    // Both ends inside the artwork, so the touch never leaves the old button.
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
    XCTAssertTrue(
      waitUntil(timeout: 5) { self.miniPlayerIsHittable(in: app) },
      "Dragging down from the artwork did not dismiss the full-screen player."
    )
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
    resetRecentlyPlayed: Bool = false
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
    if resetRecentlyPlayed {
      app.launchArguments.append("-UITestResetRecentlyPlayed")
    }
    if let initialSection {
      app.launchArguments += ["-UITestInitialSection", initialSection]
    }
    app.launch()
    return app
  }

  private func openRootSection(_ title: String, in app: XCUIApplication) {
    if app.tabBars.buttons[title].waitForExistence(timeout: 3) {
      app.tabBars.buttons[title].tap()
      return
    }

    let identifier = "RootSection.\(title.lowercased())"
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

    if app.buttons[title].waitForExistence(timeout: 3) {
      app.buttons[title].tap()
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
        if identifiedElement.exists {
          return
        }
      }
      if app.staticTexts[title].exists || app.buttons[title].exists {
        return
      }
      app.swipeUp()
    }

    XCTAssertTrue(
      (identifier.map { element(identifier: $0, in: app).exists } ?? false)
        || app.staticTexts[title].exists
        || app.buttons[title].exists,
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

  private var isRunningOnPad: Bool {
    #if canImport(UIKit)
      return UIDevice.current.userInterfaceIdiom == .pad
    #else
      return false
    #endif
  }
}
