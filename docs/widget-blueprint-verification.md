# iOS widget and shortcut blueprint verification

Implemented and checked on October 11, 2026. Scope includes the pasted blueprint and the user's added repeat requirement. Existing deployment targets, widget kinds, shortcut titles/phrases/parameters/list, App Group identifier, signing configuration, and watch interfaces were preserved. The pre-existing build-number changes from 27 to 28 were retained.

## Changes

- Repeat Once replays the current song once, then turns off. Continuous repeat advances through the selected playlist/collection and wraps to its first song. A directly selected song repeats itself without adding autoplay recommendations to its repeat cycle. The selection distinction is persisted; older saved multi-song queues retain collection semantics. Shuffle order is preserved across a repeat cycle. Manual Next continues to leave the current song and retain the repeat setting.
- All 15 discoverable iOS actions now have individual `IntentDescription` metadata. The ten suggested shortcuts and their phrases are unchanged. Repeat descriptions and confirmation dialogs include collection versus single-song behavior.
- `SharedThemeDefinition` is the single named-theme factory for System, Light, Dark, Neuro, SMOCUS, Evil, and Nwero. Serializable sRGB colors, appearance rules, backgrounds, Aurora values, text, accents, surfaces, borders, highlights, shadows, widget shape metrics, and typography travel in schema-version-1 App Group state. The app saves this state before requesting widget reloads. Providers read it into entries independently of the app singleton.
- Missing/corrupt/unknown theme data falls back to Dark. Version-zero selection state migrates to the complete definition. Existing app appearance preferences remain the migration source when shared state is missing. Arbitrary custom IDs and valid definitions use the same persistence/rendering path; no editor was added.
- All three iOS widgets use the shared SwiftUI raised surface: gradient, upper/leading highlight, lower/trailing shade, inset stroke, and clipped internal shadow. Nwero uses a static Aurora treatment. Constrained rendering modes use semantic foregrounds and supported accented artwork behavior.
- Medium radio divides available content width, minus the shared gap, in a 2:1 ratio. Its leading column contains artwork, station label, song, optional artist, and the existing Play Live intent. The trailing column contains the people icon, formatted listener total, label, and last successful update date/time. Zero is valid; invalid/missing totals show a dash and Unavailable.
- Radio metadata uses the existing model and endpoint. Metadata requests have a 10-second timeout; artwork requests have a 5-second timeout and an 8 MB accepted-response limit. Cached content and its successful-fetch timestamp survive failure. Late responses are rejected when a newer snapshot is already stored. Cached radio artwork is protected from ordinary artwork pruning/account cleanup. Successful unchanged app polls save their timestamp but do not repeatedly reload widgets. The 900-second widget request remains a scheduling request, not a real-time guarantee.
- New listener/update labels include the project's existing translated locales. New action descriptions follow the existing English metadata convention; other locales currently fall back to English.

## Shortcut inventory

| Action | Description behavior covered |
| --- | --- |
| Play Radio | Start the live station |
| Toggle Playback | Pause/resume loaded song or radio |
| Next Track | Skip queued song; queue prerequisite and radio restriction |
| Previous Track | Previous song or restart after three seconds |
| Play Favorites | Shuffle/repeat/timer options; sign-in and nonempty collection |
| Play Downloads | Available downloaded songs and playback options |
| Play Playlist | Selected playlist/options; personal-playlist sign-in |
| Favorite Current Song | Add once; loaded song, sign-in, radio restriction |
| Start Sleep Timer | Timed or song-end stop; timed-only radio |
| Open Search | Open music search |
| Open Lyrics | Open lyrics for loaded song |
| Show Current Song | Return title and artist |
| Toggle Repeat | Off, once, continuous collection/direct-song behavior |
| Toggle Shuffle | Shuffle queue; restore original order |
| Transport | Selected pause/resume/next/previous/restart command |

## Verification

Environment: Xcode 27 SDK; iPhone 17 Pro simulator running iOS 26.5. App and widget deployment targets remain iOS 26.5. The app scheme also built its embedded watch products for compatibility; watch-specific interfaces were not redesigned.

- The repeat change was implemented first and passed its initial 19 focused simulator tests before widget work resumed.
- Final unit/rendering run: 52 tests passed (51 Swift Testing cases plus one XCTest render matrix), covering shared theme serialization, migration, validation, custom persistence, compiled intent descriptions, radio decode/offline cache, content-change detection, proportional columns, artwork storage, playback snapshots, radio lifecycle, sleep timers, queues, and actual cached-audio intent behavior.
- The render matrix captures 67 PNGs: eight theme/appearance variants across all seven supported widget/family combinations, a custom definition, three failure cases, two constrained rendering modes, four localized larger-text cases, and first-launch state. Production widget content views are shared with the simulator renderer; padding and system corners are approximated in the render harness.
- Reviewed all library/playback theme-size renders and radio theme, size, and edge-case sheets. Tested long titles, missing artist/artwork, zero/huge/unavailable totals, stale timestamps, German/Japanese/Chinese, and RTL layout. Larger accessibility text is capped at XL within fixed widget bounds; VoiceOver retains full metadata. Secondary localized timestamps may truncate in the smallest tested columns.
- Installed app: radio deep link opened the radio screen; real metadata updated song/listener values; Play Live reached “Live and playing”; Pause returned to “Live Ready.” This validates the existing app playback service/routing, not a Home Screen widget tap.
- Final UI navigation run: all three tests passed—cold search launch, search/library/radio/home routes, and the selected-playlist widget destination. The first combined run's root-navigation test failed because Search's navigation title was absent despite its captured hierarchy showing the correct search screen. Only that test assertion changed, to use the existing `SearchBrowse.Featured` identifier; app routing did not change. Total selected coverage across the successful runs: 55 tests.
- Simulator Shortcuts displayed the ten suggested actions and Play Radio's exact individual description. All 15 discoverable descriptions also passed the compiled-metadata test. The repeat action was opened in a verification shortcut editor, but its description panel could not be reached after the UI bridge lost coordinate input again.
- Cleanup: radio was paused; simulator Twinskaraoke and Shortcuts were terminated; iPhone 17 Pro was shut down; a final simulator inventory showed no booted devices. The compact window was closed by returning to the original Device Hub window and restoring its original iPhone 16 Pro / iOS 26.5 selection. Xcode, Device Hub, and other pre-existing desktop apps were left as found. Builds/tests finished; no task process remains running. Build/result artifacts remain available for review. The simulator may retain the verification shortcut draft; its saved state could not be checked or cleared through the unavailable UI bridge.

Representative render sheets:

![Radio themes and custom definition](/Users/yitzyryp/Documents/Twinskaraoke/docs/widget-blueprint-renders/themes.jpg)

![All seven supported sizes in Neuro](/Users/yitzyryp/Documents/Twinskaraoke/docs/widget-blueprint-renders/sizes.jpg)

![Failure, localized text, constrained-mode, and first-launch cases](/Users/yitzyryp/Documents/Twinskaraoke/docs/widget-blueprint-renders/edge-cases.jpg)

## Remaining verification limits and personal steps

- Installed Home Screen widgets could not be added through the native UI automation: gallery results appeared visually but had no actionable accessibility rows, and coordinate clicks returned `noWindowsAvailable`, including in Device Hub's compact window. Actual widget button taps, OS corner treatment, background removal, and final tinted/accented recoloring therefore need checking on a physical iPhone. SwiftUI constrained-mode renders do not emulate the operating system's final recoloring.
- The renderer displays a system placeholder for the playback progress view; its actual WidgetKit presentation and live timer appearance need the installed-widget check. Source retains the existing progress behavior and explicitly applies the shared accent.
- Compiled action metadata and Play Radio's Shortcuts description are verified. The remaining individual description panels, including repeat, still need a physical-device check. Sign-in-dependent favorites/personal-playlist actions were not exercised against a real account.
- Confirm `group.org.magnettileman.Twinskaraoke` is registered and assigned to both App IDs in the Apple Developer team. Existing local entitlements match, but simulator success does not verify portal registration or physical-device provisioning. Refresh profiles only if necessary. See [Apple's App Groups setup](https://developer.apple.com/documentation/xcode/configuring-app-groups). No extra capability or legacy SiriKit extension is needed for description changes.
- On the iPhone, select each theme, return to the Home Screen, check the supported sizes, test Play Live and other widget controls, and inspect individual actions in Shortcuts. Allow WidgetKit scheduling latitude; 900 seconds is not a guaranteed refresh deadline.

## Reproduction and artifacts

Unit/render results: `/tmp/twins-blueprint-regression.xcresult` (52 passed; combined run also contains the original UI assertion failure). Successful UI rerun: `/tmp/twins-blueprint-navigation.xcresult`. Logs have the matching `.log` names. Derived data: `/tmp/twins-blueprint-build`. Earlier successful visual result: `/tmp/twins-blueprint-final.xcresult`. Full PNG attachments are available in the result bundles. The saved sheets above are representative exports from that successful visual run; subsequent changes affected persistence/tests and explanatory comments rather than their layouts. Final cleanup removed one unused localization key and organized explicit widget project references; project/localization syntax and the final diff were rechecked.

```sh
xcodebuild -project Twinskaraoke.xcodeproj -scheme Twinskaraoke \
  -destination 'platform=iOS Simulator,id=C8D985CA-5D82-4DC2-8695-45D9F571E6AE' \
  -derivedDataPath /tmp/twins-blueprint-build -parallel-testing-enabled NO \
  -resultBundlePath /tmp/twins-blueprint-regression.xcresult \
  -only-testing:TwinskaraokeTests/WidgetBlueprintTests \
  -only-testing:TwinskaraokeTests/WidgetRenderingTests \
  -only-testing:TwinskaraokeTests/AppThemePaletteTests \
  -only-testing:TwinskaraokeTests/SystemIntegrationTests \
  -only-testing:TwinskaraokeTests/RadioLifecycleTests \
  -only-testing:TwinskaraokeTests/SleepTimerTests \
  -only-testing:TwinskaraokeTests/PlaybackQueueStateTests \
  -only-testing:TwinskaraokeTests/SystemIntentPlaybackTests \
  -only-testing:TwinskaraokeUITests/SystemIntegrationUITests test
```

Use a new result-bundle path when repeating the command.
