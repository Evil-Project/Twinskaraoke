# iPhone 16 Pro tester follow-up — September 14

The tester used the latest iOS 27 testing-branch commits. The exact iOS build is unknown; RC is an assumption, not verified evidence. The supplied text describes the recordings; the original videos and launch-hang stacks were not available for this review.

## Download hesitation

Confirmed source defect: `immediatelyPlayableURL` required an in-memory validation entry. On a cold process that entry was missing, and `startStreamPlayback` consulted the separate AudioCache directory without resolving the committed Downloads file. This could fetch another copy from the network. Tracks played before relaunch already had that separate cache, explaining their different behavior. The size of Favorites increases restoration work but is not required to trigger this path.

The fix resolves Downloads before the streaming cache/network. Completed and newly validated downloads receive an atomic validation receipt beside their audio. Receipts retain source identity, expected duration, file modification time and size. Reuse checks fresh filesystem attributes; URL resource-value caching previously could conceal replacement or deletion. Rotating recognized authentication parameters do not invalidate resource identity. Older downloads without receipts are validated individually off-main, then gain a receipt; there is no required full-library decoder warmup. Unreadable existing downloads are preserved and reported instead of silently starting a network request. Bulk enqueue also avoids repeating decoder probes on the main actor.

## Playback restoration

Added an atomic, serial off-main session store for the current song, queue order, original shuffle context, repeat mode, playback position and prior playing state. Queue/control changes, periodic playback checkpoints (at most every ten seconds), and leaving the foreground save the session. Restoration runs off-main and retries on protected-data availability/activation. It cannot replace a new user playback request. The mini-player returns paused; the app does not start audio automatically. Seek while restored/paused updates the resume position. Live-radio playback is not restored as a finite song.

The relaunch UI test uses a separate session file so it cannot overwrite a normal session. It verifies the mini-player, nonzero position, and paused state after termination/relaunch.

## Tabs and playlist cards

Removed the iOS 27 early return that disabled short upward-scroll reveal. The existing reveal hold/cooldown and owner-scoped teardown remain, and SwiftUI's tab-bar declaration stays constant. Search prominence is maintained during changes. Transition logs now include controller identity, mode and tab frame for comparing any remaining geometry problem. These use Apple's public [tab-bar minimization API](https://developer.apple.com/documentation/uikit/uitabbarcontroller/tabbarminimizebehavior).

Playlist grid cells explicitly use their full rectangular layout as the interaction shape, including the transparent space around title/count content. Final tap-region and accessory-animation feel require device verification.

## Cancel a playlist download

The playlist actions menu now exposes **Cancel Playlist Download** while its songs are in flight. Cancellation covers queued transfers, active tasks, promotions, deferred requests and pending repair work for the selected songs. It retains completed files and unrelated songs. The batch clears its pending journal/state before starting other queued work. Per-song cancellation generations prevent an asynchronous validation warmup from re-enqueuing cancelled tracks; clearing all downloads also invalidates older warmup batches. A track shared with another playlist is the same download task, so cancellation affects that shared task.

## Other log findings

No new crash, keyboard, Bluetooth, microphone, permission or network regression can be established from the supplied summary. App-switcher termination is distinct from a crash. The two launch-hang events still need diagnostic stacks/durations before assigning a cause. Now Playing elapsed publication is already limited to changes of elapsed second/rate, with elapsed logging every fifteen seconds; this review did not establish measurable harm from that cadence. No entitlements or system-volume APIs were changed to hide system denial logs.

## Validation

The prior branch commit `f2e4b8c` passed [hosted run 34766460815](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34766460815), resolving the earlier scrub-control test failures.

This follow-up passed 288 unit tests and the new playback-session relaunch UI test on the local iOS 26.5 simulator (`/private/tmp/tester-feedback-verified.xcresult`). The final enqueue-only adjustment also passed all 29 download tests (`/private/tmp/tester-download-final.xcresult`). The final Release simulator build also passed (`/private/tmp/tester-feedback-release.log`). The iOS 27 workflow now includes the session relaunch test. Hosted validation of these new changes and device verification remain necessary.

Device checks: download an unplayed playlist, terminate/relaunch, then play/shuffle offline; compare first-play latency with already-played songs. Reopen with a saved position and confirm paused restoration/resume. Cancel a playlist batch with queued/active songs and confirm completed files remain and unrelated downloads continue. Scroll down then slightly upward to check accessory reveal/geometry, and tap the blank title/count portions of playlist cards. Capture app commit, exact OS build, and any remaining frame/latency logs with the result.
