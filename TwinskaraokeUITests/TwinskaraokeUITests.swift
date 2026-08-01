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

    scrollToVisibleItem("Dance", in: searchApp)
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
        compactRootTabExists(section, in: app),
        "Expected compact tab \(section) to be visible."
      )
    }
  }

  func testSidebarPreservesDrillDownStateAcrossSectionChanges() throws {
    guard isRunningOnPad else {
      throw XCTSkip("The sidebar shell is only available on iPad.")
    }

    XCUIDevice.shared.orientation = .landscapeLeft
    addTeardownBlock {
      XCUIDevice.shared.orientation = .portrait
    }

    let app = launchApp(initialSection: "search")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(
      app.staticTexts["Discover"].waitForExistence(timeout: 10),
      "Expected the landscape iPad app to expose its sidebar."
    )
    XCTAssertFalse(
      app.tabBars.firstMatch.exists,
      "The sidebar detail should not render a second root tab bar."
    )
    XCTAssertEqual(
      app.buttons.matching(identifier: "AccountToolbarButton").count,
      1,
      "The sidebar detail should expose one account toolbar button."
    )

    openVisibleItem(
      "Twinskaraoke Top 100",
      identifier: "SearchCategory.TwinskaraokeTop100",
      in: app
    )
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "TopChartCollection.Destination",
        in: app,
        timeout: 8
      ),
      "Expected Search to open the Top 100 collection."
    )

    openRootSection("Home", in: app)
    XCTAssertTrue(
      app.navigationBars["Home"].waitForExistence(timeout: 8),
      "Expected Home to own the detail navigation bar after switching sections."
    )
    XCTAssertFalse(app.navigationBars["Search"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    XCTAssertEqual(app.buttons.matching(identifier: "AccountToolbarButton").count, 1)

    openRootSection("Search", in: app)
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "TopChartCollection.Destination",
        in: app,
        timeout: 8
      ),
      "Expected Search to keep its drill-down destination after switching sidebar sections."
    )

    XCUIDevice.shared.orientation = .portrait
    let sidebarHidden = expectation(
      for: NSPredicate(format: "exists == false"),
      evaluatedWith: app.staticTexts["Discover"]
    )
    wait(for: [sidebarHidden], timeout: 10)
    XCTAssertTrue(compactRootTabExists("Search", in: app))
    XCTAssertTrue(
      accessibleElementExists(
        identifier: "TopChartCollection.Destination",
        in: app,
        timeout: 8
      ),
      "Expected Search to keep its drill-down destination when the shell changes size."
    )
  }

  func testSidebarPreservesLibraryDrillDownAcrossSectionChangesAndResize() throws {
    guard isRunningOnPad else {
      throw XCTSkip("The sidebar shell is only available on iPad.")
    }

    XCUIDevice.shared.orientation = .landscapeLeft
    addTeardownBlock {
      XCUIDevice.shared.orientation = .portrait
    }

    let app = launchApp(initialSection: "library")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(
      app.staticTexts["Discover"].waitForExistence(timeout: 10),
      "Expected the landscape iPad app to expose its sidebar."
    )
    XCTAssertTrue(
      app.navigationBars["Library"].waitForExistence(timeout: 8),
      "Expected Library to own the detail navigation bar before opening a destination."
    )

    openVisibleItem("Artists", in: app)
    XCTAssertTrue(
      app.navigationBars["Artists"].waitForExistence(timeout: 8),
      "Expected Artists to open from Library."
    )

    openRootSection("Home", in: app)
    XCTAssertTrue(
      app.navigationBars["Home"].waitForExistence(timeout: 8),
      "Expected the sidebar to switch to Home and transfer navigation ownership."
    )

    openRootSection("Library", in: app)
    XCTAssertTrue(
      app.navigationBars["Artists"].waitForExistence(timeout: 8),
      "Expected Library to retain its Artists destination after switching sections."
    )

    XCUIDevice.shared.orientation = .portrait
    let sidebarHidden = expectation(
      for: NSPredicate(format: "exists == false"),
      evaluatedWith: app.staticTexts["Discover"]
    )
    wait(for: [sidebarHidden], timeout: 10)

    XCTAssertTrue(compactRootTabExists("Library", in: app))
    XCTAssertTrue(
      app.navigationBars["Artists"].waitForExistence(timeout: 8),
      "Expected the Library destination to survive the live shell resize."
    )
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
    scrollToVisibleItem("New This Week", in: app)
    XCTAssertTrue(
      app.staticTexts["New This Week"].waitForExistence(timeout: 8),
      "Expected New to render its latest playlist shelf."
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
    scrollToVisibleItem("New & Recent", identifier: "Radio.HistorySection", in: app)
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

    XCTAssertTrue(
      app.buttons["Library Actions"].waitForExistence(timeout: 5),
      "Expected Library to expose its actions menu."
    )
    app.buttons["Library Actions"].tap()
    XCTAssertTrue(
      app.buttons["New Playlist"].waitForExistence(timeout: 5)
        || app.staticTexts["New Playlist"].waitForExistence(timeout: 5),
      "Expected Library actions menu to contain New Playlist."
    )
  }

  private func launchApp(initialSection: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-UITestMode", "1"]
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
    if app.buttons[identifier].waitForExistence(timeout: 3) {
      app.buttons[identifier].tap()
      return
    }

    let identifiedSidebarCell = app.cells.containing(.staticText, identifier: identifier).firstMatch
    if identifiedSidebarCell.waitForExistence(timeout: 3) {
      identifiedSidebarCell.tap()
      return
    }

    if app.staticTexts[identifier].waitForExistence(timeout: 3) {
      app.staticTexts[identifier].tap()
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

    let labeledRootButton = app.buttons
      .matching(NSPredicate(format: "label == %@", title))
      .firstMatch
    if labeledRootButton.waitForExistence(timeout: 3) {
      labeledRootButton.tap()
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

  private func compactRootTabExists(_ title: String, in app: XCUIApplication) -> Bool {
    if app.tabBars.buttons[title].waitForExistence(timeout: 2) {
      return true
    }
    return app.buttons
      .matching(NSPredicate(format: "label == %@", title))
      .firstMatch
      .waitForExistence(timeout: 3)
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

  private func openMiniPlayer(in app: XCUIApplication) {
    let miniPlayer =
      app.buttons["MiniPlayerBar"].firstMatch.exists
      ? app.buttons["MiniPlayerBar"].firstMatch
      : app.otherElements["MiniPlayerBar"].firstMatch

    XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8), "Missing mini-player bar.")
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
