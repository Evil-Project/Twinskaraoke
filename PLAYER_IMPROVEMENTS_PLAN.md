# iOS player improvements

## Scope

- Preserve local signing and entitlement settings. Remotes and main were synced at b3a7db7.
- Keep the full-player dismiss handle below the top safe area, widen it to 50pt, and reserve its own layout space.
- Keep Search separate from the other tabs on smaller iPhones using the native search tab configuration; reproduce and verify on compact and Max devices.
- Track the finger during both mini-player expansion and full-player collapse. Use projected release movement to settle, handle cancellation, and respect Reduce Motion.
- Add a sleep timer for music and radio: 15, 30, 45, and 60 minutes, remaining time, and cancellation. Put the control in the player, with timing owned by the audio service so it survives player dismissal and screen locking.

## Implementation and validation

1. Inspect native tab behavior and available simulators; choose the smallest supported fix for compact Search.
2. Fix handle geometry and implement interactive expansion with matching dismissal behavior.
3. Implement timer state and player controls, including radio access.
4. Build and run relevant unit/UI checks. Verify compact and Max phone layouts, cancellation/reversal of player gestures, music/radio expiry, and iPad layout where available.
5. Record outcomes and any device-only validation still needed here.

## Acceptance criteria

- Handle is visible below Dynamic Island without overlapping content.
- Search has a separate native affordance on compact and Max phones.
- Player follows upward and downward drags before release and settles predictably.
- Timer can be started, inspected, replaced, and cancelled; expiry pauses playback without clearing the queue.
- Local signing changes remain intact.

## Findings and implementation

- Search report clarified: iPhone 16 Pro on iOS 27 beta. iPhone 17 Pro on the installed iOS 26.5 runtime has a detached Search button. Apple now provides `UITabBarController.prominentTabIdentifier`; the iOS 27-only compatibility adapter calls its documented public Objective-C setter so the iOS 26 SDK can still build the app. Verification on iOS 27 remains required; no iOS 27 SDK/runtime is installed here.
  - Reference: https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier
- Handle: 50pt capsule with a 60 × 44pt hit area, positioned using the injected top inset; content reserves the handle row.
- Gestures: expansion and dismissal both track global finger translation, then settle using projected travel. Animation completion controls artwork handoff. The artwork target uses the stationary player coordinate space rather than the moving global frame.
- Timer: playback-owned deadline, foreground reconciliation, music/radio overflow menus, active countdown and cancellation. Expiry also clears automatic resume intent after an audio interruption. English and German strings added; other languages fall back to English.
- Validation completed on iOS 26.5:
  - 16 focused unit tests passed (gesture projection, reversal/clamping, timer expiry, cancellation, replacement).
  - Both UI flows passed on iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch: repeated open/dismiss, swipe-up expansion, handle geometry, starting the timer, preserving it through player dismissal, and cancelling it.
  - The concurrent Max/iPad run had two Max UI failures. Both Max checks passed when rerun on their own with temporary diagnostics removed; simulator load is a possible cause, not a confirmed diagnosis.
  - Debug simulator builds pass, the string catalog parses, and `git diff --check` is clean.
- Device follow-up: verify detached Search on the reported iPhone 16 Pro/iOS 27 beta; evaluate gesture feel with a real finger and Reduce Motion; exercise timer expiry with locked-screen music and live radio. Automated expiry tests validate the deadline/callback, not actual locked-screen audio output.
- Existing project signing and entitlement edits were preserved. No commits or pushes made.

## Follow-up: continuous finger tracking

- Device feedback found premature expansion and dismissal that moved only after release. The earlier endpoint-only UI checks did not cover these failures.
- Replaced SwiftUI gesture-state cancellation inference with a shared UIKit pan recognizer that distinguishes movement, release, and cancellation. Cancellation returns to the starting state; it never commits based on distance. Tap actions cannot settle an active pan.
- The overlay explicitly captures presentation progress at its view boundary and receives unanimated pan updates, so its lazy geometry content updates throughout movement.
- Added a debug-only UI-test probe sampling the rendered layer on a display link while the finger is down. The regression check requires both substantial movement and multiple distinct intermediate positions in both directions, followed by a held partial dismissal that returns to expanded.
- First Pro Max run passed the continuous-movement test, artwork drag protection, and the sleep-timer flow. Final Pro Max validation passed all 19 selected tests, including the strengthened intermediate-position check, cancellation unit tests, repeated dismissal, and artwork taps. These tests run on iOS 26.5; the updated gesture feel still needs confirmation on the physical device that reported the issue.
- Debug and Release simulator builds passed after the gesture correction. The display-link probe is compiled only for Debug and installed only with the dedicated UI-test launch argument.

## Follow-up: intermittent jump on a tiny opening drag

- The opening surface still combined independent tap and pan recognizers. It now uses one contact recognizer, with position and window height captured at touch-down. It cannot fall through from a drag to a tap, and a held release discards stale flick velocity.
- Found an unguarded cross-surface path: the full player remains mounted offscreen, and its closing handler maps upward movement to progress 1. Hit testing alone is insufficient protection for bridged recognizers. Added explicit eligibility checks and drag ownership: inactive surfaces cannot start, update, cancel, or finish the active surface's drag.
- Added a deterministic state regression that injects the inactive full-player events during a 1% mini-player drag and requires progress to remain 1%. Added repeated UI checks for held 6/10/18pt drags, subsequent normal taps, and transport-button taps.
- Final contact/ownership validation passed all 15 selected tests on iPhone 17 Pro Max / iOS 26.5: contact math, cross-surface ownership, cancellation, six held tiny drags, continuous movement, normal taps, transport taps, repeated dismissal, and the timer flow. The device-reported intermittent event still needs confirmation on hardware; the previously unguarded cross-surface overwrite is now covered deterministically.
- The contact/ownership version also passes the Release simulator build. It remains uncommitted on `player-improvements` for Xcode testing.

## Follow-up: short upward gestures sometimes fail to open

- Device feedback confirms the jumping appears resolved, but some upward flicks/drags only enlarge the accessory and return to minimized.
- Opening no longer reuses the full-screen dismissal's quarter-screen threshold. It uses an 80pt projected opening threshold (scaled down on short windows), with at least 20pt actual upward travel to reject tiny jitter. Projection still allows a reversal to cancel; settling starts only after release.
- Stationary terminal samples preserve recent movement velocity; a hold longer than 100ms clears it. Small initial sideways jitter waits for direction to resolve instead of immediately rejecting the gesture.
- Exclusive tap/drag recognition, frozen window coordinates, and cross-surface drag ownership remain intact.
- Added unit coverage for short flicks with stationary final samples, held release, initial sideways jitter, distance/velocity thresholds and reversals. Added repeated UI coverage for 40pt flicks and held 85pt drags.
- Validation passed: all 31 selected tests on iPhone 17 Pro Max / iOS 26.5, including short gestures, tiny held drags, continuous finger tracking, transport taps, source ownership and dismissal math. Release simulator build and `git diff --check` also pass. Physical iOS 27 beta confirmation remains required.

## Follow-up: accessory gesture competition

- Device feedback reports unchanged missed openings for both held drags and flicks; threshold tuning did not resolve the reported issue.
- The custom opening recognizer had default prevention rules: a parent accessory press/pan could recognize first and fail it before upward movement. Opening now coexists with recognizers on ancestor views, while keeping normal arbitration with same-view/child recognizers (including transport controls). No further release-threshold changes.
- Uses UIKit's public subclass prevention hooks: https://developer.apple.com/documentation/uikit/uigesturerecognizer/canbeprevented(by:).
- Added a Debug-only, opt-in UI-test fixture that installs a competing ancestor long press before upward movement. The new repeated short-flick/held-drag test passes with the fix. Negative control with only the prevention change removed fails the opening assertion, confirming the regression test detects this cancellation path. The fixture is absent from normal launches and Release builds.
- First corrected run also passes tiny held-drag cancellation, transport-button taps and continuous finger tracking (4 UI tests). Final restored-code run passes all 29 selected tests (27 unit tests plus ordinary and competing-gesture opening UI tests). Release simulator build and `git diff --check` pass. The simulated competing recognizer demonstrates the failure mechanism, not direct reproduction of the native iOS 27 beta recognizer on hardware.

## Follow-up: stable window-owned opening contact

- Hardware still reports about half of opening attempts failing. Prior center-only gesture tests and simulated ancestor competition did not reproduce that device failure.
- Moved the single tap/drag recognizer out of the native accessory's SwiftUI gesture host and onto its window, installed by the stable root view. Weak UIKit markers report visible mini-player and transport bounds in that same window. Contacts outside the bar, behind a modal, or while the full player is active are rejected at touch-down.
- The contact keeps its window coordinates and ownership after acceptance, without depending on accessory host layout updates. Both native placements have an explicit full-height touch region. Ordinary transport taps fail the opening recognizer; upward drags beginning over controls can now open too.
- Expanded UI checks to six opening attempts from center, top/bottom padding and artwork edge, with and without a competing parent press. Extended the transport check to tap and then drag from the same button. Initial window version exposed an attachment lookup error; resolving the attached UIWindow directly fixed the six-position opening test.
- Final validation: all 33 selected tests pass on iPhone 17 Pro Max / iOS 26.5 (27 unit and 6 UI tests), including edge starts, control-origin drags, competing gestures, tiny held drags, finger tracking and sleep-timer flow. Release simulator build and `git diff --check` pass. Changes remain uncommitted on `player-improvements`.
- This removes host lifetime and hit-region dependencies; it does not establish which native iOS 27 beta event caused the user's intermittent failure. Physical confirmation remains necessary.

## Follow-up: capture the actual device failure

- User reports no improvement with the window-owned version. The device bug remains unresolved; simulator success must not be reported as resolution.
- Added console tracing prefixed `[PlayerGesture D1]`: installed host/window and OS version, touch eligibility and region bounds, raw movement/cancellation, release decision, model progress and animation apply/completion. No song/account content is logged. Gesture decisions are unchanged. Tracing is temporarily enabled in both Debug and Release because the affected device is running the Release configuration; remove or gate it after diagnosis.
- Device procedure: run the app from Xcode on the affected phone (Debug or Release), filter the console for `PlayerGesture`, reproduce a failed upward swipe, and share the filtered output from the D1 installation line through the failed attempt (plus a successful attempt if possible). This distinguishes missing input, region/eligibility rejection, cancellation, and rendering/settling failure before another behavioral change.

## Device-confirmed cause: touch rejected during closing animation tail

- The failed D1 trace shows `inBar=true`, `modal=false`, `expanded=false`, `owner=nil`, `progress=0`, but `animating=true` and therefore `eligible=false` / `receive=false`. Closing animation completion arrives immediately afterward. The successful trace differs by `animating=false`, allowing recognition and normal finger tracking. This identifies the failed attempt's cause directly, rather than inferring it from simulator behavior.
- Mini-player contact eligibility now depends on committed collapsed state and no active drag, not animation completion. A held contact can survive closing completion; first movement uses the existing token invalidation and source ownership to take over. No threshold or native host changes in this correction.
- Added deterministic tests for contact during pending close, completion between touch-down and movement, late completion during a new opening, and tap reversal. The trace remains enabled in Release and is versioned `[PlayerGesture D2]`.
- Validation passed: all 19 focused tests (17 unit tests and the tiny held-drag / live finger-tracking UI checks) on iPhone 17 Pro Max / iOS 26.5; Release simulator build and `git diff --check` also pass. Physical confirmation of the corrected close/reopen sequence remains requested. Changes remain uncommitted on `player-improvements`.
- User subsequently confirmed the close/reopen gesture issue is fixed on device.

## Follow-up: artwork stays attached while closing

- User reports that the cover floats above the full-player background while dragging it down. The shared morph hides the real artwork and interpolates a separate root-overlay image toward the mini thumbnail, independent of the translating surface.
- Restrict that detached morph to opening. Closing keeps the real artwork inside the moving/clipped player background, including after release and throughout cancellation back to expanded. Retain transition source through settlement so lifting the finger cannot switch to a floating copy.
- Added state regressions for multiple closing progress values, completed and cancelled closing, tap dismissal, and immediate reopening with a late closing completion.
- Validation passed: all 13 selected tests (10 presentation-state tests plus live finger tracking, artwork-origin dismissal and artwork tapping) on iPhone 17 Pro Max / iOS 26.5. Release simulator build also passes. Visual feel on the user's device remains to be confirmed; changes are uncommitted on `player-improvements`.

## Follow-up: contain the opening morph within the player

- User confirms closing looks better, but wants to retain the opening animation without the image crossing the player boundary.
- Moved the opening artwork layer inside the full-player surface, before its clipping and translation. Convert its original window-space path into surface-local coordinates, retaining the same growth and travel while clipping the image and shadow at the moving background edge.
- Keep the mini-player thumbnail visible underneath until the advancing background covers it, avoiding a missing image while the opening morph is outside the clipped region. Closing continues using the attached real artwork.
- Added geometry coverage for coordinate conversion, preserved path/size, and clipping bounds across opening progress. All 18 selected tests passed (6 geometry, 10 presentation-state, and 2 opening/finger-tracking UI tests) on iPhone 17 Pro Max / iOS 26.5. Release simulator build also passes. Device visual confirmation remains requested; changes are uncommitted on `player-improvements`.

## Reference-based closing settlement

- Inspected the user's 8.63-second Apple Music screen recording in the local Photos library. The reference shows a coordinated surface contraction and cover dip/return, not an image flying freely over a sliding panel.
- Added a release-only 0.58-second settlement: freeze the release surface/artwork and native pill/thumbnail bounds, contract the existing background, fade the full controls into a non-interactive mini row, and move/shrink the cover with a small right/down arc before returning to the thumbnail. Artwork stays clipped within the contracting surface, whose lower edge accommodates the dip.
- The final handoff crossfade starts after the cover has reached its exact thumbnail bounds, avoiding two offset copies. The native accessory remains the actual resting player and retains its controls.
- While the finger is down, or a dismissal is cancelled, the attached-cover behavior remains. Missing artwork/destination and Reduce Motion use the existing transition. Closing does not block new mini-player input; reopening invalidates the old settlement token and clears its visual state.
- Added geometry tests for endpoints, dip/return, containment across release positions, and inline/sidebar target sizes; state tests cover commit-only activation, fallback and immediate reopening. A dedicated Debug artwork fixture and display-link UI probe now exercise the real rendered settlement; existing UI fixtures had no artwork and would otherwise skip this path. These test hooks are absent from Release.
- Validation: all 18 initial unit/UI tests pass on iPhone 17 Pro Max / iOS 26.5, including rendered intermediate settlement frames and the surface's dip below the pill. Tiny held-drag and transport-button regressions also pass. The artwork landing test passes independently on iPhone 17 Pro / iOS 26.5.
- An experimental in-app screenshot hook blocked enough frames to fail the frame-count test; that hook was removed. Reviewed frames from an external simulator recording instead, confirming the contracting rounded surface, contained cover and final pill handoff without blocking app rendering.
- Release simulator build and `git diff --check` pass. Changes remain uncommitted on `player-improvements`. This is a reference-based implementation, not a claim to reproduce Apple's private animation parameters exactly; final timing/feel needs the user's device evaluation.

## Follow-up: remove tinted pill handoff and smooth the return

- Device feedback: the contracted background lingered over the native pill, and the cover's bounce/return felt stuttery. Removed the replica mini-player controls and the late whole-surface crossfade. The actual background now clears by 58% of the release animation, leaving only the moving artwork during the final return.
- Replaced the piecewise sine dip and early stop with one cubic Bézier path, continuously eased across the full 0.5-second duration with zero endpoint velocity. The cover stays opaque until the exact native-thumbnail endpoint; the underlying thumbnail is hidden only during settlement, avoiding offset duplicate images.
- The full-player content-opacity environment now changes once per settlement, instead of every animation frame. Controls use a separate short opacity animation. Finger-down geometry, reopening eligibility, token invalidation, Reduce Motion and missing-artwork fallbacks remain unchanged.
- Added regressions for early background clearance, continuous velocity and continued movement through the final return. The display-link UI probe now measures the actual cover rather than the contracting background. All 20 focused geometry, state and UI tests pass on iPhone 17 Pro / iOS 26.5, including rendered landing and live finger tracking. Device smoothness still needs confirmation; simulator tests do not establish parity with Apple Music.
- Release simulator build and `git diff --check` pass. Changes remain uncommitted on the checked-out `player-improvements` branch.

## Follow-up: device reports plain slide instead of artwork settlement

- User's D2 logs show successful gestures and animation completion on iOS 26.6.1, but do not establish whether the cover-settlement branch ran. The simulator landing test injects artwork and therefore cannot exclude missing real artwork as a device-only fallback cause.
- Added Release-visible `landing request`, `landing selected` and `landing complete` diagnostics. These report all selection gates (Reduce Motion, image availability, canvas and destination/source frames), the selected slide/cover-curve mode and settlement state. No image URLs, additional image loads or per-frame logging are introduced.
- Do not retune the curve speculatively. Device logs from one close are needed to distinguish a skipped settlement from a rendering failure while the settlement is active. No visual or gesture changes in this diagnostic follow-up.

## Review handoff

- User confirmed the current transition feels good after rebuilding. Every recorded closing request in the latest iOS 26.6.1 device logs selected `cover-curve`, with artwork present and no skipped gates; rapid reopening interrupted settlement as intended. The preceding inconsistent appearance remains unexplained, rather than attributed to the diagnostic-only update.
- Final regression pass: all 54 selected unit/UI tests passed on iPhone 17 Pro / iOS 26.5, covering gesture contacts and ownership, dismiss metrics, artwork geometry and rendered landing, live finger tracking, transport taps, tiny held drags, and sleep-timer behavior/UI. The Release simulator build passed after the final code change.
- Submit from `player-improvements` to upstream `main`. Keep the local Xcode signing/bundle-identifier changes and CarPlay entitlement override out of commits. Retain Release device diagnostics for follow-up; iOS 27 Search prominence remains pending verification on that OS.
