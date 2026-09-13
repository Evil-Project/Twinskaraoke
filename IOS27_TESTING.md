# iOS 27 restoration test branch

Branch: `fix/ios-27-launch-restoration`, based on `3ac6257` from `modernization/ios-26-5-audit`.

Apple lists Xcode 27 RC (27A266a) and iOS 27 RC (24A435), released September 9, 2026. This development Mac has Xcode 26.6 (17F113), Swift 6.3.3, and iOS 26.5 simulators. The iOS 27 runtime behavior still needs device verification.

## Changes to verify

- Downloads restore from an atomic metadata manifest, then reconcile with read-only directory enumeration. A failed decoder probe no longer deletes downloaded audio or queues an automatic repair. Failed audio probes are not memoized. Failed/ongoing restoration has a visible state and can retry after unlock or foregrounding.
- Keychain reads preserve the actual OSStatus. Unavailable reads are not cached as missing and cannot clear persisted iOS account metadata. API request construction fails instead of sending an anonymous request when Keychain is unavailable.
- Public and Library playlist loads can retry after failure, preserve prior results, and expose errors. Malformed playlist responses throw instead of becoming empty success. Requests have bounded retry and mounted tabs retry unfinished loads after foregrounding/unlock.
- On iOS 27, Search explicitly enables automatic search activation and assigns the documented prominent identifier after tabs appear. Attachment retries cover late installation and layout/window updates. The custom scroll-reveal gesture is disabled on iOS 27 so UIKit manages minimization.

## Device checks

1. Install this branch over an existing signed installation with downloads and an account. Keep the same bundle ID/signing identity so existing app data and Keychain entries remain accessible.
2. Cold-launch offline. Open Downloaded immediately. Existing songs should return without re-downloading; a loading/error state must not claim the library is empty. Play several saved containers, including affected files, and verify artwork and duration.
3. Repeat after reboot and unlocking. Lock/unlock during startup, then foreground. The account must remain signed in once protected data becomes available.
4. Open Search and Library with connectivity disabled, restore connectivity, and pull to refresh or background/foreground. Both lists should recover. A failed refresh must preserve previously loaded playlists.
5. During restoration, remove one download, remove all, and complete a new download. Removed entries must not return; completed downloads must remain after relaunch.
6. Check Search separation on cold launch, tab switches, search cancellation, rotation, and iPad resizing. Verify mini-player placement while scrolling. iOS 27 intentionally uses the native scroll-reveal threshold.
7. Verify the same flows on iOS 26.5 to check backward compatibility.

Enable the app's debug logging before reproducing. Export logs covering the cold launch and recovery, and include device model, OS build, Xcode build, affected container types, and a recording of Search/mini-player behavior. Logs include filesystem paths/errors, restoration state/protected-data availability, Keychain status (never the token), playlist retry errors, audio duration probe errors, and prominence assignments.

## Limits and follow-up

Xcode 27 / Swift 6.4 builds now use the typed iOS 27 prominence property. Builds with the local older SDK retain the availability- and selector-guarded public Objective-C API bridge. Apple also documents SwiftUI `TabRole.prominent`; replacing `.search` with that role changes search semantics, so this branch retains `.search`. Validate the bridge with the RC SDK/device before merging. No iOS 27-specific header/duration behavior has been measured locally.

Uncertain explicitly downloaded audio is preserved. Playback/stem cache probes also preserve files when validation or source metadata is unavailable. A genuinely damaged file may require explicit removal and re-download; it is no longer automatically deleted after a failed decoder probe. Legacy migration preserves the original copy until explicit download removal.

Sources checked September 11, 2026:

- [Xcode 27 RC release](https://developer.apple.com/news/releases/?id=09092026h)
- [Apple release listing](https://developer.apple.com/news/releases/?id=02262026)
- [UIKit prominentTabIdentifier](https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier)
- [UISearchTab automaticallyActivatesSearch](https://developer.apple.com/documentation/uikit/uisearchtab/automaticallyactivatessearch)
- [SwiftUI TabRole.prominent](https://developer.apple.com/documentation/swiftui/tabrole/prominent)

The subsequent full API audit fetched Apple’s current RC Markdown directly; it supersedes the beta-era search snapshot from the initial restoration pass. See [IOS27_COMPATIBILITY_AUDIT.md](IOS27_COMPATIBILITY_AUDIT.md) for the broader findings and remaining release gates.

## Local validation

Xcode 26.6 simulator build passed. The final targeted run passed 45 tests (46 executions including parameterized coverage), with zero failures, on iPhone 17 Pro / iOS 26.5. Suites: LaunchRestorationTests, DownloadManagerTests, SearchLifecycleTests, and SecurityRegressionTests. Coverage includes unavailable credentials, malformed playlist responses, retry after failed initial load, non-destructive audio discovery, signed URL rotation, and reconciliation with concurrent download changes.

The URL-encoding security test now injects an absent credential instead of reading the unsigned simulator app's Keychain; a separate test verifies that unavailable credentials stop request creation.


## September 12 recheck additions

- Refresh a signed audio URL while keeping its song/resource identity; playback must preserve the existing download and its source metadata even if an audio probe temporarily fails.
- Confirm sidecar/backup/staging files and directories alone never appear as downloaded songs.
- Verify watch account and audio-cache flows with the companion privacy manifest included.
- Test cache regeneration and downloads after stopping playback, backgrounding/locking, and relaunching. Downloads now use a persistent background URLSession and an atomic pending queue. Start several transfers, background/lock, allow a system termination (not a user force-quit), and relaunch. Verify completion, cancellation, and no duplicate downloads. User force-quit follows system restrictions.
- Record both Xcode and simulator/device OS build. CI labels Xcode `27A266a` plus simulator `24A435` as the audited RC pair. Other successful builds are explicitly labeled preliminary; their toolchain version alone no longer fails CI.

- With asynchronous activation, test immediate Play/Pause, selecting a second song while activation is pending, phone-call interruption/resume, media-services reset, and AirPlay/Bluetooth route changes. Playback must wait for activation and late callbacks must not undo Pause.

## Additional September 13 checks

- During separation, lock/unlock, stop playback, cancel, and start another song. Old work must not publish stems or write into a deleted job directory. Measure CPU-only separation time and memory on iOS 27.
- Adjust the visible native volume slider, hardware buttons, Bluetooth and AirPlay routes, and VoiceOver controls.
- Open two iPad windows. Video rotation, overlay placement, sprite dragging, and mini-player floors must remain in the owning window. Backgrounding a window must stop its overlay animation.
- Exercise standard iOS 27 artwork/detail pushes, completed/cancelled swipe-back, and rapid taps. Navigation must remain responsive and gestures must not start playback.
