# iOS 27 RC compatibility audit — rechecked September 13, 2026

## Result

The remaining source findings are addressed on `fix/ios-27-launch-restoration`: separation compute/cancellation, persistent background downloads, nondestructive cache probes, native volume and standard iOS 27 push navigation, and scene-owned orientation/overlays. Full RC compatibility still requires an exact-RC runner and signed-device integration checks; simulator success cannot establish those results.

This pass inventories all 217 Swift files in the iOS app and shared source directories (about 51,400 lines; 31 imported module names), inspects the corresponding build settings/resources, and reviews the phone/watch session bridge and pinned dependency implementations. The inventory is repository-wide static inspection; it is not a claim that every code path was executed or formally verified. Standalone Mac/TV feature parity is outside this iOS audit; Release builds also verify that shared code compiles for those targets.

## Official baseline

The directly fetched Apple Markdown pages identify themselves as **iOS & iPadOS 27 RC Release Notes** and **Xcode 27 RC Release Notes**. Search-engine snapshots previously returned older beta notes. Apple documents scene lifecycle and launch-screen requirements, SwiftUI state-initialization changes, visible-tab selection enforcement, new text-selection interactions, and SDK-dependent presentation/menu changes. [iOS 27 RC notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)

Xcode 27 RC includes Swift 6.4 and requires macOS 26.6 or later on Apple silicon. This Mac has Xcode 26.6 / Swift 6.3.3 and an Intel simulator toolchain. Installing just a new simulator would not provide the RC compiler/SDK. [Xcode 27 RC notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)

## Fixes in this pass

| Area | Finding and change | Evidence |
| --- | --- | --- |
| Search tab | Swift 6.4 builds now use typed `UITabBarController.prominentTabIdentifier`; older SDK builds retain the guarded public ObjC bridge. Search keeps its semantic role and automatic activation. | `Twinskaraoke/App/TabBarMinimizeCoordinator.swift`; [Apple prominence API](https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier) |
| Phone/watch account | An unavailable phone credential could publish a signed-out descriptor or reply, causing the watch to delete its token. Descriptor availability and token replies now distinguish unavailable from signed out; foreground/unlock republishes the descriptor. | `AuthManager`, `WatchSessionPublisher`, `WatchSessionLink`, `WatchAuthManager`; token-reply regression test |
| Video history | A temporary credential failure could select the guest history bucket. An unresolved account now waits for a definitive account and retries on foreground/unlock; it does not load or save a guest bucket merely because Keychain is unavailable. | `VideoResumeStore`; account-identity regression test |
| Request builders | Library songs, playlist pagination, first-party translation, and QR approval still bypassed the typed credential read. They now fail/retry through their error paths instead of silently dropping authentication. | `LibrarySongsViewModel`, `PlaylistListLoader`, `LyricsTranslationService`, `AuthManager`; pagination regression test |
| Uploaded songs | A transient credential failure could become a permanently loaded “sign in” state and clear the list. It now preserves songs and remains retryable. | `UploadedSongsViewModel` |
| Privacy manifest | The existing manifest covered preferences and file timestamps but omitted system uptime used for playback timing, haptic throttling, and UI timers. Added SystemBootTime reason `35F9.1`; existing tracking and collected-data entries remain intact. | `Twinskaraoke/PrivacyInfo.xcprivacy`; [Apple required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) |
| Regression isolation | URL/lyrics/request tests now inject credentials instead of reading the unsigned test host’s Keychain. A separate test ensures unavailable credentials prevent anonymous request construction. | `LyricsLifecycleTests`, `SongModelTests`, `ModernizationRegressionTests`, `LaunchRestorationTests` |

The privacy declaration requirement predates iOS 27; it is a distribution gap found during this audit, not a newly introduced RC rule. [Apple required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## September 13 implementation fixes

### Separation execution and cancellation

The app now vendors the MIT-licensed swift-spleeter 0.2.0 source with a small compatibility patch. `separateFile` runs its chunk loop and file writers in the caller's task, checks cancellation around inference and each write, and returns only after those operations have stopped. App cleanup therefore cannot race an orphaned stream producer. The application no longer uses the dependency's legacy streaming API.

On iOS 27 both `MLModelConfiguration.computeUnits` and the task-local `MLTensor` compute policy use CPU-only execution. This avoids GPU/Neural Engine use during foreground-to-background transitions without adding a provisioning-dependent entitlement. Separation may take longer; measure foreground/background completion, battery use, and memory on hardware. Ordinary background audio does not grant unlimited CPU execution time, and iOS may suspend the app when playback stops. [Background Inference entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference), [MLTensor compute policy](https://developer.apple.com/documentation/coreml/mlcomputepolicy)

### Persistent downloads and cache preservation

Offline downloads use an identified background URLSession with delegate callbacks. An atomic Application Support journal records accepted songs and generation tokens before network work starts. Relaunch reattaches existing tasks, recovers completed-transfer receipts, and queues outstanding entries. The app delegate forwards background-session events; its completion waits until delivered files are processed. Cancellation removes journal ownership and stale completions cannot delete replacement downloads. Journal reads wait for protected data rather than replacing unavailable data with an empty queue. A user force-quit remains subject to Apple's background-session restrictions. [Background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)

Disposable playback/stem-cache probes now preserve files after unreadable headers, unavailable source metadata, decompression errors, or duration mismatch. Playback source identity ignores the same known signing parameters as downloaded audio while retaining content selectors. Explicit eviction and successful cache compression remain separate maintenance operations. Regression tests exercise the actual playback lookup and compare preserved bytes.

### Public controls and navigation

The player displays MPVolumeView with documented track/thumbnail image customization: a thin continuous track and an invisible thumb with the normal system touch target. It no longer searches the view's internal UISlider hierarchy or synthesizes slider events. System routing, volume buttons, and accessibility are owned by the native control. [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview)

On iOS 27 artwork destinations use standard push navigation, with the app's horizontal content-swipe guard cancelling row touches before Back. The legacy private-name zoom recognizer suppressor is disabled on iOS 27; the older iOS 26 workaround remains version-gated. Simply restoring native zoom was tested and rejected: hosted run 34724539014 reproduced accidental playback from a tap during dismissal. The existing swipe-back regression remains enabled in CI. `ClearPresentationBackground` has no active call sites.

### Scene ownership

Orientation leases are keyed by the actual hosting UIWindowScene, and the application delegate consults the supplied window. The last video opt-out requests portrait only in its own scene. Each SwiftUI root owns a Shimeji overlay and engine; a hosting-window probe attaches it to the correct scene. Sprite dragging and mini-player geometry update that engine, and disappearance/backgrounding stops its timer and display link. Test two windows, resizing, external displays, and video rotation on hardware. [UIKit scene guidance](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)

### Device-only integration checks remain

Audio playback, interruptions, media-services reset, AirPlay/Bluetooth, lock-screen commands, CarPlay, Photos authorization/save, camera QR capture, browser sign-in, paired-watch recovery, and background download/separation behavior need real-device verification. The unit suite uses controlled inputs and does not establish permission prompts, hardware routes, signed Keychain access, or live server compatibility. Update both phone and companion watch builds when testing the new unavailable-credential reply.

## API and implementation coverage

“No new source requirement found” means the inspected code does not match a documented migration trigger; it does not mean runtime certification.

| Area/modules | Inspection | Assessment |
| --- | --- | --- |
| SwiftUI/UIKit lifecycle | `TwinskaraokeApp`, `ContentView`, scene manifest, `LaunchScreen.storyboard`, build-generated plist keys | Required scene and launch setup present. Verify built artifact and RC launch. |
| SwiftUI state/Observation | All state declarations and six explicit `State(initialValue:)` assignments; observation bridge; main-actor models | Explicit initializers have no competing declaration value. No `@Entry` defaults or document-protocol migration trigger found. Swift 6.4 preview compilation passed; exact RC compiler validation remains pending. |
| Tabs/navigation/search | All root enum cases, selection binding, sidebar selection, tab role, mini-player accessory, UIKit coordinator | Selection constrained to visible root cases. Typed API path added; iOS 27 uses standard push navigation with a content-swipe guard. |
| Text/menus/presentation | Text selection, gestures, menu content, custom presentation and trait APIs | No `.textSelection(.enabled)`, custom `UIPresentationController`, or overridden presentation trait chain found. Menu appearance changes remain a visual check. |
| Foundation/network | Shared request/data/decoding helpers, direct URLSession call sites, URL/path escaping, account-scoped caches | Credential bypasses fixed. No `canOpenURL` calls or broad ATS exception found. Live endpoints not exercised. |
| Security/AuthenticationServices/CryptoKit | Keychain status handling, token cache, committed-session marker, browser continuation cancellation, QR approval, watch handoff | Unavailable credentials preserved; signed-device restoration still required. |
| AVFoundation/AVKit/CoreMedia/MediaPlayer | Engine/session setup, route/interruption/reset notifications, now-playing commands, crossfade, Pillarbox playback, volume/route picker | Session notifications hop to main actor; framework usage remains supported by current SDK. Native volume replaces internal-subview access; hardware routes remain unverified. |
| CoreML/Accelerate/Spleeter | Model load, separation producer/consumer, trim reader/writer, cancellation and output publication | Structured file separation and CPU model/tensor policy implemented; hardware performance remains unverified. |
| Foundation/Compression/Darwin storage | Download manifest/scan, caches, file metadata, compression, ZIP reads, deletion and promotion paths | Prior launch-restoration fixes retained. Privacy uptime declaration added. Protected-data/upgrade testing remains required. |
| Photos | Add-only authorization and async change requests in `ImageSaver`; saved-artwork lifecycle | Purpose string present; injected permission/write tests available. Real Photos check pending. |
| Camera | `AVCaptureSession`, serial session queue, non-zero preview-bounds gating, permissions, runtime errors | Camera purpose string present; no iOS 27-specific migration requirement identified. |
| WebKit | Captcha web view, navigation policy, external links | Public API usage; interactive sign-in/CAPTCHA check pending. |
| CarPlay | Scene delegate, template count limits, command integration, cancellation/disconnect cleanup | Uses scene API and system template limits. Entitlement/provisioning and vehicle controls need a signed device. |
| WatchConnectivity | Context publishing, token reply, activation/reachability, teardown/account scoping | Unavailable-state protocol fixed; paired-device check pending. |
| UserNotifications | Authorization, settings, migration, completion delivery | Existing lifecycle tests cover control flow; real notification delivery pending. |
| CoreHaptics/QuartzCore/CoreGraphics | Timers, display-rate use, animation geometry, haptic engine control | No deprecated application status-bar or `UIScreen.main` references found. Device animation/route check remains. |
| Combine/Network/OSLog/os | Notification delivery, network monitor, cancellation ownership, debug logs | Main-actor hops and cache locks reviewed at API boundaries; static review does not prove all races absent. |

## Dependencies and build checks

The pinned releases match the latest upstream releases returned during this audit:

- [SDWebImage 5.21.7](https://github.com/SDWebImage/SDWebImage/releases/tag/5.21.7)
- [SDWebImageSwiftUI 3.1.4](https://github.com/SDWebImage/SDWebImageSwiftUI/releases/tag/3.1.4)
- [Pillarbox 19.0.0](https://github.com/SRGSSR/pillarbox-apple/releases/tag/19.0.0)
- [swift-spleeter 0.2.0](https://github.com/jiyimeta/swift-spleeter/releases/tag/0.2.0)

Latest release status is not an iOS 27 compatibility guarantee. The Spleeter source inspection above is more informative than its version number. The deployment target remains iOS 26.5.

A dedicated `.github/workflows/ios27-compatibility.yml` records compiler/SDK/runtime versions, builds and analyzes Release, runs the complete iOS unit suite and three navigation UI checks, and retains results. It identifies the audited RC as Xcode build **27A266a** plus simulator build **24A435**, preferring that runtime when installed. The workflow now accepts successful preview builds/tests and labels their scope explicitly; a green preview run is not RC validation. The hosted run confirms **27A5252f / beta 6**, matching GitHub’s `xcode-27` image README. Its preview results must not be reported as RC validation. [GitHub runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

## Validation results

- iOS 26.5: **260 unit tests passed**, 277 executions including parameterized cases, zero failures or skips. Result: `/private/tmp/ios27-api-audit-ios-verified.xcresult`.
- After updating the preview-exposed tab assertions, all **11 modernization regression tests passed** again on iOS 26.5; `/private/tmp/ios27-api-audit-tab-tests.xcresult`.
- watchOS 26.5: **43 unit tests passed**, zero failures or skips. Result: `/private/tmp/ios27-api-audit-watch.xcresult`.
- iOS Release build and static analysis passed without diagnostics using Xcode 26.6; `/private/tmp/ios27-api-audit-release.log`.
- Mac and TV Release builds passed using the installed Xcode 26.6 toolchain; `/private/tmp/ios27-api-audit-mac.log` and `/private/tmp/ios27-api-audit-tv.log`.
- Built iOS app inspection confirms `UIApplicationSceneManifest`, bundled `LaunchScreen.storyboardc`, camera/Photos purpose strings, and all three required-reason API declarations in `PrivacyInfo.xcprivacy`.
- Plist syntax, workflow YAML parsing, and `git diff --check` passed.
- The first full run exposed request tests that read the unsigned host’s Keychain; those now inject credentials, and the final full run above passed. The first compile also identified the video-history caller that needed to handle an unavailable descriptor.

Hosted run: [iOS 27 compatibility — source commit 60b12c3](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34646312864). The runner reports Xcode 27 beta 6 (**27A5252f**), Swift 6.4, and the iOS 27 preview SDK. Release build and static analysis passed, including the typed prominence API path; the only recorded Release warning disables App Intents metadata extraction. All three navigation UI checks passed. The unit run passed 255 of 260 tests; five legacy tab-coordinator tests produced 10 assertion failures because they expected the custom recognizer that is deliberately disabled on iOS 27. Those tests now assert zero custom recognizers on iOS 27 and retain the prior expectations on iOS 26.5. The source implementation did not require a change for these failures. The follow-up run below verifies the corrected assertions. The exact-RC toolchain gate will reject this preview toolchain even if all tests pass; it was skipped in this run after the unit-test failure. A green iOS 26.5 test run is backward-compatibility evidence, not iOS 27 runtime evidence.


## September 12 recheck

The [follow-up run for 6713e72](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34648734939) passed Release compilation/static analysis, **all 260 unit tests**, and **all three navigation UI tests** on Xcode 27 beta 6. Only the explicit RC-toolchain check failed. This resolves the five test-expectation failures from the initial preview run; it does not establish RC or signed-device compatibility.

### Additional fixes

- **Signed URLs during playback:** `playableURL(for:)` still used literal URL equality, although prewarming already used `sameAudioResource`. Rotating a signature could therefore delete downloaded audio and schedule repair on playback. The playback path now uses the same resource comparison. A regression invokes the real playback lookup with changed signatures and an undecodable file, then verifies both audio and source metadata remain intact.
- **Download discovery:** any `main.*` entry previously counted, including backup sidecars and directories. Discovery now requires a regular file with a supported audio extension and excludes staging files. It still does not open an audio decoder. A filesystem regression covers sidecars, compressed leftovers, staging files, directories, and an undecodable committed audio file.
- **Companion privacy:** the watch executable uses app preferences and file timestamps but had no manifest in its own bundle. Added `TwinskaraokeWatchApp/PrivacyInfo.xcprivacy` with `CA92.1` and `C617.1`. Shared uptime haptic code is compiled only for iOS, so it is not declared for watch. Apple requires declarations in each executable's bundle; the phone manifest alone is insufficient. This requirement predates iOS 27. [Required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- **RC validation:** the old workflow gate checked Xcode alone. It now also verifies the selected simulator runtime and retains its inventory, preventing an RC SDK plus preview runtime from being reported as a complete RC run.

### Guidance and call-site cross-check

Apple's freshly fetched iOS RC notes add a Hardware Security section for arm64e.x1/CPA2 since the September 11 snapshot; Xcode RC notes are unchanged. Enhanced Security remains a deliberate capability adoption with separate testing requirements, not a mandatory migration for this app's current configuration. [iOS RC notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), [Enhanced Security](https://developer.apple.com/documentation/xcode/enabling-enhanced-security-for-your-app)

The stricter TLS note applies to listed system management/install/update processes, not a blanket new URLSession rule. The app has no broad ATS exception; live server/CDN connections still need RC device checks. No active first-party uses were found for the new RemoteMediaSession push-token issue, deprecated on-demand resources, PHAssetResource.originalFilename, external noninteractive display scene roles, renamed navigation minimization APIs, or drag-interaction delegate callbacks. SwiftUI artwork uses the existing image pipeline, with no AsyncImage call sites affected by its new automatic HTTP caching behavior.

The remaining credential convenience reads were traced: phone playlist/favorite loaders defer unavailable credentials and receive foreground/unlock retries; best-effort upload metadata hydration can return unhydrated metadata, and watch credential reads can display awaiting-phone until sync recovers. Neither is proof of completed signed-device restoration. Mutating API requests still use the throwing credential path.

### Additional limitations made explicit

`AudioCacheStore` handles disposable playback/stem caches separately from explicit downloads. It still deletes cache entries after failed header/decompression probes or missing/mismatched source metadata and compares source URLs literally. A transient read or rotated signature can cause cache regeneration and renewed model inference. The explicit-download preservation fixes do not establish that all generated caches survive transient failures. Include cache reuse and locked/background playback in device testing; the background inference finding above also applies to regeneration.

Downloads use a default URLSession with completion handlers, not a persistent background URLSession. Audio background mode does not establish that downloads survive suspension/termination when playback stops. This is an existing lifecycle limitation, not a newly documented iOS 27 removal; test starting a download, stopping audio, locking, and relaunching.

### Recheck validation

- **29 targeted tests passed**, 30 executions including parameterized cases, zero failures/skips on iOS 26.5. Includes both new filesystem/playback regressions. Result: `/private/tmp/ios27-recheck-tests.xcresult`.
- Workflow YAML parsing and runtime selection checks passed: RC preferred with mixed runtimes; preview fallback records its non-RC build.
- Watch Release build passed using Xcode 26.6. The built `Twinskaraoke Watch App.app/PrivacyInfo.xcprivacy` matches the source manifest and contains both required-reason categories. Build log: `/private/tmp/ios27-recheck-watch.log`.


## CI failure follow-up

Full logs for [ef5d6f7](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34686439999) confirm Release build/static analysis, **262 unit tests**, and three UI checks passed. The only failing step was the strict RC version gate: the runner used Xcode `27A5252f` and simulator `24A5423a`.

The workflow now reports RC/preview scope in the job summary instead of failing solely for the unavailable RC pair. Compilation, analysis, and test failures still fail the job. `-collect-test-diagnostics never` disables verbose simulator diagnostic collection, which timed out for 600 seconds after the tests passed; ordinary logs and xcresult bundles remain artifacts.

The full logs exposed a main-thread synchronous audio activation warning. iOS 27 SDK builds now use Apple's asynchronous activation API. Playback entry points wait for activation, coalesce repeated requests, and discard callbacks invalidated by interruptions; Pause cancels queued playback. Background preparation cannot replace a newer user playback request. Older SDK builds retain their supported activation API. [Apple asynchronous activation](https://developer.apple.com/documentation/avfaudio/avaudiosession/activate(options:completionhandler:))

App Intents metadata notices, the duplicate accessibility class in Apple's simulator frameworks, and debugger lookup messages were not build/test failures. No framework files or diagnostic output filters were modified to hide them. Hardware routes and interruption recovery still require device verification.

Local validation for the CI/audio follow-up: the full iOS 26.5 run passed 266 unit tests plus three navigation UI checks (269 tests, 286 executions), then all five final activation-coordination regressions passed after adding background-request precedence. The RC/preview job-summary scripts were checked with both toolchain pairs, and workflow YAML/diff validation passed. Hosted verification follows on the testing branch.


## Post-green source recheck

Revisited the current Apple iOS/Xcode RC notes and inventoried all 217 iOS/shared Swift files (31 imported modules), with targeted rereads of activation/cancellation, download reconciliation, authenticated playlist restoration, tab prominence, scene orientation, and privacy resources. The fresh API call-site scan found no additional use of the documented migration triggers listed above (including legacy status-bar/screen access, document protocols, drag callbacks, RemoteMediaSession, on-demand resources, and renamed navigation minimization APIs). This is static inspection, not execution of every path.

Found one further timing defect in the asynchronous activation change: after Pause cleared pending playback, a late background file/stem preparation could enqueue a replacement before activation completed. Cancellation now prevents such preparation from repopulating the queue; an explicit new Play request can still proceed. Added regressions for late preparation after Pause and explicit Play after Pause. All seven activation tests passed locally (`/private/tmp/ios27-cancellation-recheck.xcresult`); the pushed source will receive the complete hosted suite.

The previous [green run for c275f86](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34688359285) passed 267 unit tests and three UI tests, with no main-thread activation warning or 600-second diagnostics timeout. It exercised the preview runtime, not the RC. Outstanding release checks remain those described above, including real signed Keychain/protected-data recovery, physical audio routes, and suspension/relaunch behavior. The September 13 section supersedes the source issues listed in earlier audit passes. Repeated successful simulator runs do not eliminate these gaps.

## September 13 validation

Local Xcode 26.6 / iOS 26.5: Debug app build passed, then all **272 unit tests** passed (289 parameterized executions, zero failures). A second run passed those 272 tests plus the swipe-back UI regression. After adding two transfer-receipt tests and deferring completions while protected data is unavailable, the full download suite passed **25 tests** (26 executions). The subsequent stale-event-batch regression also passed with the full download suite (**26 tests**, 27 executions). An earlier individual-test filter selected zero tests and is not counted as validation.

Hosted iOS 27 build/analyzer/navigation validation passed for source commit `2224b60`; see the final result below. Real system-termination/background-session delivery, signing, physical volume routes, and inference performance require the device checklist.

The first complete hosted run, [d55cc58](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34724539014), passed Release build/analyze and all **275 unit tests**. Three UI checks passed; the new swipe-back regression failed because native zoom still accepted an outgoing-row tap. The subsequent standard-push change addresses that behavior. The direct job log contained 16,271 lines; the CLI's cached run log was incomplete and was not used to diagnose the failure. Compiler warnings were limited to App Intents metadata extraction.

## Final hosted result

[Run 34749091694](https://github.com/Mag1cByt3s/Twinskaraoke/actions/runs/34749091694) passed for `2224b6093bb1b33c62e38a27297a601e04a205d2`: Release build and static analysis, all **275 unit tests**, and all **four UI tests**, including the previously failing swipe-back/no-accidental-playback regression. The complete direct job log (16,314 lines) contains no compiler errors; warnings concern App Intents metadata extraction only. The runner remains Xcode 27 beta 6 (`27A5252f`) with the preview runtime, so exact-RC and signed-device verification remain outstanding. This documentation-only update does not change the tested source.

## Native-control follow-up

Music seeking, equalizer bands, effect strength, and karaoke level now use SwiftUI Slider with `sliderThumbVisibility(.hidden)` on all supported iOS versions. Video already uses SwiftUI Slider through Pillarbox and now hides its thumb as well. Crossfade retains whole-second values without the stepped initializer, so it does not add tick marks. Custom detent haptics and hand-drawn slider gestures were removed. Audio levels still throttle live changes and commit the final value on release. Buttons, toggles, pickers, menus, steppers, text fields, and loading indicators already use native controls. Artwork gestures, sprite dragging, and the tested navigation/presentation gestures serve different interactions and are not slider replacements.

Public APIs: [Slider thumb visibility](https://developer.apple.com/documentation/swiftui/view/sliderthumbvisibility(_:)), [MPVolumeView customization](https://developer.apple.com/documentation/mediaplayer/mpvolumeview).

Native-control validation on iOS 26.5: Debug compilation passed, settings persistence/transition-choice UI regression passed, and the native playback-slider interaction/UI-presentation test passed. Screenshot inspection confirms a continuous playback bar without ticks or a thumb. The audio-free catalog fixture cannot verify an engine playback timestamp; that assertion was removed after confirming the fixture limitation, and the test is explicitly scoped to control interaction and presentation. System volume rendering/routing still requires a physical device. These two UI checks are now included in the iOS 27 workflow.
