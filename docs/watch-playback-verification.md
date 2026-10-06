# Watch playback and downloads verification

Updated 6 October 2026.

## Using the watch

- The watch follows the account signed in on the iPhone. There is no separate watch sign-in button.
- The player’s **Audio Output** button opens Apple’s system Now Playing controls for the active audio route. It does not transfer playback between devices. Explicit standalone ownership is selected separately in **Downloads → Playback Device** (also available in Account).
- Choose **Apple Watch while the iPhone is reachable**, before leaving the phone. The choice persists offline and across app launches. A change of playback device leaves playback paused; press Play on the selected output.
- Swipe right on a song in Home, Songs, Favorites, or a playlist to choose **Download to Watch**. The player’s **Options** sheet offers the same action for songs with an audio source.
- Completed downloads appear in **Downloads**. They retain song metadata and audio in persistent watch storage, outside the automatically evicted playback cache. The current explicit-download limit is 512 MB. Failed transfers expose Retry; transfers and saved songs can be removed.
- Press Play with Apple Watch selected to use the watch's Bluetooth audio route. Radio still requires an internet connection.
- A disconnected phone cannot take audio ownership away from a watch. Reconnect to change output. This prevents both devices from independently starting audio.
- Sign-out and account switching clear the previous account's watch queue, credentials, caches, and explicit downloads when the watch receives the account change.

## Implementation

The existing playback managers and single WatchConnectivity delegate on each device remain in use. The shared session carries a session ID, owner, ownership epoch, revision, track/radio identity, queue, playing state, position, repeat/shuffle state, account generation, and command ID/sequence. Immediate messages carry controls; application contexts carry the latest playback/account state for reconnection.

Only the phone grants an output change. It stops phone audio before granting the watch ownership. The watch persists a relinquished grant before requesting phone ownership, so a lost reply or a restart cannot restart the former output. Incoming commands do not echo back as new commands. Old ownership epochs, account generations, duplicate commands, reordered sequences, and retired controller processes are rejected. Phone revision numbering persists across launches.

Watch audio uses asynchronous long-form audio-session activation and validates downloaded files before playback. Background URLSession downloads retain their temporary file before returning from the delegate, then validate audio and atomically save a manifest. A cancelled or previous-account transfer cannot recreate a removed download.

Successful favorite saves notify the matching account on the companion to invalidate its favorites cache and reload. Reconnection and foreground activation refresh favorites from the server. Refreshing does not send another toggle. Failed saves restore the previous star state.

The redundant bottom queue button is replaced by **Options** for Download, Favorites, and Sleep Timer. The queue remains one swipe left and has a VoiceOver action. Sleep timer commands go to the audio owner; only that owner runs expiry, and both devices mirror the deadline or end-of-song setting.

Playlist play/shuffle is one command, preserving the chosen starting song. Full queues are retained rather than truncated at 100 tracks. Large protocol payloads use LZFSE compression with a version marker; previous JSON snapshots remain readable. Oversized-message failures explain the playlist limit rather than suggesting the phone disconnected.

Account playlists can be fetched through the reachable phone using its active credentials, guarded by account identity and generation, with independent watch fetching as fallback. Missing optional playlist flags no longer prevent an entire library response from decoding. Token replies are bound to the requested account and generation. An expired watch credential triggers a phone refresh, clears stale account access, and rejects reuse of the same rejected credential. Delayed authentication failures are checked against the request credential so they cannot revoke a newer session. Personal details retain inline account songs as fallback while the same authenticated detail loader as iPhone fetches full audio metadata. Loading and account-sync states are visible.

The watch artwork request callback is explicitly Sendable and created outside main-actor isolation, since MediaPlayer may call it on a background thread. The repeat seek completion also explicitly crosses back to the main actor.

The existing watch layouts and controls are retained. Artwork remains locally cropped to a square; this work adds no Cloudflare image transformations.

## Verification and limits

- Crash reproduced: restoring the old artwork callback made the background-request test crash with `EXC_BREAKPOINT / SIGTRAP`. The faulting stack contains `_dispatch_assert_queue_fail`, `_swift_task_checkIsolatedSwift`, and `AudioManager.makeNowPlayingArtwork`. Restoring the nonisolated, Sendable callback passes the same test.
- Watch simulator: 72 unit tests passed, covering downloaded-file handling, persistent download restoration, damaged/missing files, late completions after removal, account response ordering, playback snapshots, ownership epochs, lost handoff replies, command ordering, queue state, favorite success/failure/account transitions, and hydration of personal playlist audio metadata with an inline-data fallback.
- Watch simulator: five focused UI tests passed for Downloads, Options, queue navigation by swipe, the Account screen without a sign-in action, and actual cached audio through AVPlayer, including pause/resume/skip and relaunch. The final run passed all 77 tests with no failures or skipped tests (`Test-TwinskaraokeWatchApp-2026.10.05_22-32-23-+0300.xcresult`).
- iPhone simulator app build passed. The focused audio-session, playback-engine, queue, and failure-handling run passed 37 tests (42 executions including parameterized cases), including all five sleep-timer tests. Xcode reported priority-inversion warnings inside the existing engine test harness.
- iPhone account/security regression run passed 21 tests.
- Paired iPhone/watch simulators reported reachable WatchConnectivity sessions. Playback initially failed to publish when the unsigned phone simulator could not read its Keychain account descriptor. Playback publication now proceeds independently of credential availability, while the watch shows account sync pending. Both simulators converged on the same phone-owned session ID and ownership epoch; terminating and relaunching both apps retained that session and advanced the phone revision from 1 to 2. This verifies startup/restart snapshot recovery, not live audio handoff or the full disconnected-command matrix.
- The standard iPhone test build is blocked by existing `CarPlayPresentationTests.swift` references to removed/private CarPlay members. Focused playback tests use a command-line exclusion of that file; the repository's CarPlay code and test file were not changed.
- Simulator UI tests use controlled fixtures. The unsigned paired simulator's unreadable Keychain prevented live account/server verification. These tests do not establish live favorites synchronization, audible AirPods output, physical-watch background continuation, or all reconnect/ownership scenarios.
- Xcode reports both the physical iPhone and Apple Watch unavailable. Physical acceptance remains outstanding; the user requested finishing with these checks pending.
- All simulators used for verification were shut down; `simctl list devices booted` returned no booted devices.

## Remaining device checks

No new Apple Developer portal capability is required by these changes. The existing watch companion identifier matches the iPhone target (`org.magnettilemanalt.Twinskaraoke`), and both targets declare background audio. Before installing on hardware, check that both targets use the intended signing team and provisioning profiles. An existing build warning reports an extension build number of 21 versus the containing app's 25; resolve that before an archive/distribution build.

On the paired physical devices, verify:

1. Signed-in library and favorites match; star/unstar on either device updates the other.
2. Sign-out, account switching, and token refresh do not expose the prior account's library.
3. iPhone output plays only through the phone's current route; watch controls and Now Playing follow track changes.
4. Select Apple Watch while connected, download a song, disconnect the phone, and play through AirPods. Exercise pause, seek, skip, repeat, and shuffle.
5. Lock/lower the watch and confirm audio continues; reconnect and confirm state converges without starting a second output.
6. Interrupt an ownership change or connection, relaunch either app, and confirm only the granted owner can output audio.

## Follow-up: player controls and watch playback (6 October 2026)

- Replaced the custom Crown gain/seek binding with Apple's `WKInterfaceVolumeControl`, selecting its local or companion origin according to the granted audio owner. This controls the actual system output instead of changing a watch-only gain while iPhone plays. The control owns Crown focus only on the player page, outside modal menus. Reference: [Apple volume control documentation](https://developer.apple.com/documentation/watchkit/wkinterfacevolumecontrol).
- The progress bar now seeks by touch position, with a preview during dragging and one committed seek on release. Playback ticks cannot write a Crown value and trigger another seek. VoiceOver retains 15-second adjustments. Seeking is bounded and rejects invalid coordinates.
- Increased the artwork allowance and moved the title/progress group lower. Requested hidden persistent system overlays on the player; the watchOS clock remained visible in the verified simulator screenshots. System navigation controls were retained.
- Sleep Timer displays a one-second countdown or End of song, and returns to its status row after selection and after the owner's timer reply.
- Personal playlist cards load missing covers from the same detail endpoint used by iPhone and render song-cover mosaics locally. Absolute image URLs supplied by the server are preserved. No additional Cloudflare transformation variants were introduced.
- Songs without inline audio metadata resolve their song detail before standalone playback or downloading. Download actions remain available for such songs. Download preparation, progress and failure explanations are visible in Options, with access-denied, missing-server-file and offline errors distinguished.
- Uncached standalone tracks stream through AVPlayer instead of waiting for a complete foreground URLSession download. Persistent explicit downloads continue through background URLSession and validated files play offline. Saved watch-specific player gain no longer mutes playback independently of the system volume.

Physical device checks remain pending by user request. Simulator tests cannot establish audible output volume, AirPods routing, real-account media access, or physical-watch background streaming/download completion.

### Follow-up verification

- Final run: **78 watch unit tests and 4 UI tests passed**, 82 total, with no failures or skips. Result: `Test-TwinskaraokeWatchApp-2026.10.06_00-55-53-+0300.xcresult`.
- A local HTTP server sends real WAV bytes through URLSession's download delegate, including the temporary-file handoff, AVAsset validation, persisted metadata and ready-file lookup. The test first reproduced an AVFoundation validation failure when staging files had no media extension. Preserving the extension made the same transport pass. This uses an ephemeral session for deterministic transport; physical background scheduling remains unverified.
- Explicit downloads now preserve supported media suffixes in staging, the manifest and persistent files. Legacy `.audio` entries migrate to a recognized suffix. A focused removal test also caught and verified the correction for choosing the saved filename before removing its manifest entry.
- UI verification played saved `.wav` downloads without a remote URL or connected phone, then skipped to the next saved song. Cached playback, pause/resume, skip and relaunch also passed.
- Touching the midpoint of a paused 30-second song moved playback to 15 seconds. Turning the Crown afterward left the paused song at 15 seconds. Sleep Timer returned to its status row after selection and displayed the countdown and End of song state.
- Larger-artwork, player-options, offline-playback and timer screenshots were inspected. The native watchOS clock remains visible. Actual system volume changes and live account-specific artwork still require hardware/live-account verification.
- Streaming startup is bounded: a song that never starts exposes a retryable connection/output error after 30 seconds.

## Follow-up: Series 9 layout and Account storage (6 October 2026)

- Removed the visible bottom volume control while keeping the native volume control mounted for Digital Crown routing to the audio owner. Actual output-volume changes still require the physical-device check.
- Reserved 44 points above player content to prevent artwork overlapping the system clock. Removed the ineffective request to hide persistent overlays. The installed watchOS SDK marks the standard SwiftUI `statusBarHidden` and `statusBar(hidden:)` APIs unavailable on watchOS; no clock toggle was added.
- Account storage now sums actual file sizes from both persistent Downloads and the temporary playback cache, including orphaned audio files. Manifest metadata is excluded. The screen refreshes when either store changes.
- Clear Cache now confirms removal of all saved downloads and cached watch audio, cancels pending downloads and metadata resolution, removes orphaned files, and prevents old transfer completions from restoring cleared songs. Local watch playback is paused and released before files are deleted. Phone playback is retained.
- The 41mm Series 9 simulator passed both focused player UI tests. Its screenshot confirms artwork below the clock and no bottom volume indicator. Result: `Test-TwinskaraokeWatchApp-2026.10.06_03-05-17-+0300.xcresult`.
- The 45mm Series 9 simulator passed **79 unit tests and 3 UI tests**, 82 total, with no failures or skips. Result: `Test-TwinskaraokeWatchApp-2026.10.06_03-10-00-+0300.xcresult`. The new unit test verifies byte totals across both stores, orphan cleanup, deletion of saved files and rejection of late completions. The Account UI test starts with three saved WAV downloads and an empty temporary cache, confirms clearing, and verifies the control becomes disabled; its screenshot shows 0 bytes. Player screenshots for both Series 9 sizes were inspected.
- `git diff --check` passed. All simulators were explicitly shut down; `simctl list devices booted` returned no booted devices. Physical Crown volume, audible output and background behavior remain pending by user request.

## PR 160 review corrections (6 October 2026)

- Account generations now belong to a persisted phone installation. Reinstalling the phone app can restart the counter; contexts from retired installations and delayed legacy contexts are rejected once the watch has adopted an installation ID. Token requests, playlist requests, commands, and live or saved playback use the same scope.
- Account transitions invalidate cached playback presentation and personal playlist detail responses. The audio ownership lease is retained until a stop is acknowledged.
- A phone control attempted while its watch-owned output is unreachable persists a request to stop that exact grant. The watch records relinquishment and stops before acknowledging, using durable WatchConnectivity user-info delivery as well as a reachable message. The phone changes ownership only after a matching acknowledgment. The rejected play command is not replayed; the user explicitly retries after recovery. Old or duplicate acknowledgments cannot revoke a newer grant.
- Relaunch download reconciliation rechecks current entry status and pending validation after awaiting the background task inventory. A completion during that wait remains available offline.
- Playlist cancellation propagates instead of falling back to an independent request for an obsolete account. Playlist detail tests wait for bounded completion rather than a fixed number of scheduler yields.
- The iPhone and widget App Group identifiers, including the store's fallback identifier, agree. Unsigned CI runs exercise widget publication with a temporary store; signed runs additionally verify entitled container access. Simulator App Intents signing respects `CODE_SIGNING_ALLOWED=NO`.

Additional paired-device checks:

1. With watch-owned playback running offline, attempt playback on iPhone. Verify the phone remains silent while waiting for the watch to stop. Reconnect; verify the watch stops, ownership returns to iPhone, and playback starts only after explicitly retrying. Repeat with either app relaunched while recovery is pending.
2. Switch accounts with saved playback and a personal playlist detail request pending. Relaunch both apps and verify that the previous account's song, queue, and playlist rows do not return.
3. Reinstall or restore the iPhone app while retaining watch app data. Verify that the new installation's lower account generation is accepted, and sign-out, token refresh, and playback synchronization recover.

Review-fix simulator validation: **347 iOS tests in 45 suites and 87 watchOS tests in 17 suites passed**, 434 total. Both suites used Xcode 27 with unsigned simulator hosts and serial test execution. New tests cover installation ordering, retired descriptors, token installation fencing, saved playback scope, exact-grant stop acknowledgments, completion during download reconciliation, playlist cancellation fallback, and stale playlist detail responses. Hardware WatchConnectivity delivery and audible output still require the paired-device checks above.

The incremental review identified two additional CarPlay cases. Root lists now show refresh failures beside retained rows and reserve space for notices, actions, and paging within the system item limit. A successfully loaded empty playlist remains authoritative on a failed reload; inline fallback rows are seeded only before any remote result exists. All **9 CarPlay presentation tests passed** after these corrections, including the two new regression tests.
