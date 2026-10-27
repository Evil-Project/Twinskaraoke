# CarPlay implementation and validation

Date: 2026-09-27

## Scope

Implementation changes are confined to `Twinskaraoke/Features/CarPlay`. Added tests are confined to `TwinskaraokeTests/CarPlayPresentationTests.swift`.

The pre-existing `project.pbxproj` and Watch scheme diffs were saved before editing and compared byte-for-byte afterward; they are unchanged. No shared player, phone UI, Watch, or TV source was edited.

The user approved using shared refresh/cache APIs. CarPlay now invalidates playlist/Favorites caches when a fresh request is needed. The phone may therefore fetch fresh data on its next request. Personal-playlist refresh uses a CarPlay-owned read of the existing endpoint, because the shared manager does not expose failure results.

## Implemented

- **F1:** Retain the queue pushed from Now Playing, update its sections on playback/queue events, release it when removed from the navigation stack, and prevent duplicate pushes. Handle push rejection.
- **F2:** Queue rows re-read the live upcoming queue. Valid selections use `skipToQueuedSong`; removed/already-passed rows only refresh. Browsing still uses the complete ordered playback context and `PlaylistPlayback` history recording.
- **F3/F4:** Store loading, successful, and failed request state independently of song arrays. Rebuilding preserves its meaning. Refresh retains cached songs and actions; failure replaces progress with an error. Cancelled responses cannot overwrite newer results.
- **F5:** Library has dedicated Favorites, My Playlists, Saved Playlists, and Browse Playlists entries. Categories deduplicate IDs and page within the same template, so navigation depth does not grow with page count. Browse can fetch additional batches.
- **F6:** Library refresh fetches Browse, Favorites, and personal playlists independently. One source failing does not erase other sources. Personal-playlist refresh errors are visible in CarPlay.
- **F7:** Fetch size is independent of display capacity. Song previews identify the visible count and full context count; queue previews identify the upcoming count. Hidden songs remain in the playback context. Row budgets reserve space for actions, status, and paging controls.
- **F8:** The fallback action uses localized “Now Playing”; the synthetic Favorites name is localized. New labels have a CarPlay-specific catalog covering the app's eight catalog locales.
- **R1/R2:** Removed custom Now Playing list rows and duplicate refresh rows. Each applicable screen has one navigation refresh action; Random calls it “New Mix”. In-flight refresh controls are disabled. No early-loading action reloads every screen accidentally.
- **R3/R4:** Radio has one playback action/indicator. Metadata rows are informational. Play, pause, and resume stay on Radio, avoiding navigation before asynchronous startup completes. The station name is not repeated as a section heading.
- Radio metadata refresh failures remain visible alongside retained metadata. Its next section says “Next on Radio”. Native ordinary Up Next is disabled in radio mode; the retained root queue tab shows read-only radio schedule information instead of a misleading empty personal queue.
- Radio metadata observations rebuild only Radio. Library-source observations rebuild Library/categories. Existing artwork caching/coalescing remains intact.
- Open Favorites reload after favorite-ID changes. Changed personal-playlist records reload matching open details. Manual playlist refresh invalidates the appropriate cache.
- Playlist push failures finish the selection callback and clear retained presentation state. Disconnect clears the new references, tasks, and observations.

## Validation

- Xcode simulator build: passed.
- iPhone 17 Pro, iOS 26.5 simulator, Xcode 27.
- This simulator reports `CPListTemplate.maximumItemCount == 12`. The implementation reserves six rows for non-song content and displays at most six songs/category entries under that limit; fetching remains 24 items per request.
- Initial tests revealed incorrect fixed-24 assumptions in the new tests. Those assertions were replaced with checks against actual rendered rows and paging actions.
- Final simulator test result: **21 tests passed in two suites** (7 CarPlay tests, including a paging test with 0/1/24/25/60 items; 14 existing queue tests).
- Final result bundle: `/private/tmp/CarPlayVerifiedBuild/Logs/Test/Test-Twinskaraoke-2026.09.27_12-43-22-+0300.xcresult`.
- Final build/test log: `/private/tmp/carplay-final-tests.log`.
- Test invocation selected only `TwinskaraokeTests/CarPlayPresentationTests` and `TwinskaraokeTests/PlaybackQueueStateTests`, with parallel testing disabled and code signing disabled for the simulator.
- `git diff --check`: passed.

The tests exercise actual `CPListTemplate`/`CPListItem` objects in a hosted iOS simulator test process. They do not establish dashboard rendering, navigation focus, or physical-car behavior.

## Not completed or not verified

- **Native navigation / four-tab design:** Kept one localized custom Now Playing action and the existing Up Next tab. Removing them remains conditional on verifying active, paused, restored, radio, and other-audio-app cases on an interactive CarPlay display.
- **Visual validation:** Device Hub exposes the iPhone simulator but no CarPlay display-switching control was found in its menus. `simctl` reports a CarPlay display port and accepted enabling it. This did not provide an interactive CarPlay window through the available UI tooling.
- **Experiments:** No complete baseline/change/revert/retest visual experiment was performed. No claim of verified scroll/focus stability, native Now Playing visibility, narrow/wide layout, rotary input, or RTL rendering is made. The existing translation catalog has no RTL locale.
- **Radio polling after leaving radio playback (E4):** Shared polling ownership is unchanged; this scenario still needs reproduction and a scoped lifecycle decision.
- **Playback errors/buffering (E7):** No additional CarPlay failure/buffering UI was added without being able to assess the native screen. Failed radio startup still relies on existing player behavior and metadata status.
- **Open-playlist freshness (E5):** Local Favorites and changed personal records are observed, and manual refresh is fresh. An external edit that causes no local observation still requires refresh; automatic remote-change detection was not added.
- **End-to-end cases:** Actual audio advancement, phone-side edits while CarPlay is open, connection/reconnection, loss/recovery of networking, and native push/pop callback behavior were not exercised interactively. Simulator template tests cover a subset, not the whole audit matrix.
- Physical vehicle/head-unit verification remains outstanding.

## Additional Tools installation and test rerun

- Installed CarPlay Simulator 4.0 from the release `Additional_Tools_for_Xcode_27.dmg` into `/Applications/CarPlay Simulator.app`; the beta download was not used.
- Disk-image checksums passed. Installed bundle passed `codesign --verify --deep --strict` with access to macOS trust services. No quarantine removal, re-signing, or Gatekeeper override was performed.
- The app launched and registered its menu-bar item. The available UI tool timed out obtaining an app window.
- Xcode's device inventory listed physical iPhones as unavailable; the standalone CarPlay tool requires a connected iPhone for interactive tests. Requested a USB-connected, unlocked phone.
- Reran the simulator regression suite: **21 tests passed**, including all seven CarPlay tests and 14 playback queue tests.
- Rerun result: `/private/tmp/CarPlayVerifiedBuild/Logs/Test/Test-Twinskaraoke-2026.09.27_12-51-08-+0300.xcresult`.
- Rerun log: `/private/tmp/carplay-installed-tool-tests.log`.
- These automated results do not establish interactive testing through the newly installed standalone tool.
