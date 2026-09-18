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

## Follow-up: remove conflicting tab ownership and protect visible genres

This section supersedes the short-distance reveal approach above. Further feedback showed that shortening the `.never` hold did not remove the conflicting UIKit/SwiftUI transition. The custom reveal recognizer, offset tracking, cooldown, behavior flips, and forced layouts have now been removed entirely. SwiftUI's `.onScrollDown` is the only minimization policy on every supported iOS version. `TabSearchProminenceCoordinator.swift` only maintains Search prominence; it does not change minimization or accessory frames. The user-visible tradeoff is the system's native scroll-up reveal distance, with no custom 72-point trigger. The accessory content still adapts to Apple's documented placement environment ([Apple accessory contract](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:))). Rapid-scroll geometry needs another device check after this change.

The claim that playback persistence was still absent does not match commit `0180d8e`: `PlaybackSessionStore`, the manager's restore/save paths, and the passing relaunch UI regression are present. The grid cell also already had a rectangular content shape; this follow-up makes that explicit at the `ZoomNavigationLink` label boundary as well.

A separate confirmed source defect affected genre screens: full-detail responses used a 30-entry cache with no visible-entry protection. Tile preview responses could evict the currently displayed songs, and its generation-keyed task would not restart after ordinary eviction. The fix gives each visible destination an ownership token, excludes owned lists from eviction, and retains them during memory-pressure cleanup. Removing one owner cannot release a list still used by another destination. Unloaded visible lists still retry when the purge generation changes.

Tile requests now retain just preview metadata rather than populating the full-song cache. Pending previews are bounded, removed when their tiles disappear, and dropped when entering a genre; new previews pause while a detail is visible. Already-running preview requests remain bounded by the existing four-request concurrency limit. The API response still contains full songs, so this reduces retained data and queued work rather than claiming a new server-side preview endpoint. Full detail loads remain prioritized, and existing detail reads refresh their cache recency.

Validation: all 288 unit tests passed (`/private/tmp/genre-tab-ownership.xcresult`). Regressions cover 40 later cache entries with the visible list retained, preview-only responses, memory pressure with multiple owners, and attachment/teardown leaving minimization untouched. Both Search navigation and mini-player interaction UI checks passed (`/private/tmp/genre-tab-ui.xcresult`). Device reproduction and hosted iOS 27 verification remain outstanding for this follow-up.


## Native upward-scroll reveal investigation (2026-09-15)

The app still declares `tabBarMinimizeBehavior(.onScrollDown)`. Its scroll
optimization modifier configures bounce, keyboard dismissal, and performance
observation; it does not replace the native scroll recognizer. The root player
gesture accepts touches only inside the mini-player, while the zoom back gesture
requires predominantly horizontal movement.

An isolated DEBUG screen (`-UITestNativeTabReveal`) contains only SwiftUI tabs,
a NavigationStack, a 200-row ScrollView, and a native bottom accessory. It excludes
the app's Search coordinator, player gestures, zoom dismissal, and scroll modifiers.
`testNativeTabRevealDiagnostic` records placement and inset-normalized scroll offset
as persistent XCTest attachments. It reports behavior rather than treating an
undocumented reveal threshold as a test assertion.

Local iOS 26.5 simulator result (`/private/tmp/native-reveal.xcresult`):
- Initial: offset 0, expanded.
- After five forward swipes: offset 3515, inline.
- After a 140-point reverse drag: offset 3385, still inline.
- After another long reverse swipe: offset 2661, still inline.

Thus the short-reverse behavior is absent even without app customization on the
local runtime. This does not establish iOS 27 behavior; the same diagnostic is now
included in its CI workflow. No production reveal behavior changed. Apple's UIKit
documentation describes expansion on scrolling back up but exposes no distance
parameter; the SwiftUI documentation describes minimization without specifying
an expansion threshold. Do not reintroduce the old timed UIKit behavior toggles.


## Restored threshold reveal (2026-09-15)

Upward movement of 72 points now requests expansion through a root-owned SwiftUI
`TabBarMinimizeBehavior` value. Shared scroll modifiers observe scroll geometry
and phase without adding gesture recognizers. The reveal is latched throughout
the gesture and deceleration; native `.onScrollDown` resumes when that scroll
reaches idle (or a new contact starts). No UIKit behavior assignment, forced
layout, fixed-delay hand-back, or custom accessory animation is used.

Experiments found that restoring the native policy midway through the next drag
misses its initial scroll event and needs a second downward swipe. Releasing at
scroll completion fixes this. The local iOS 26.5 UI test verified two threshold
reveals and first-swipe minimization between them. The same assertion is included
in iOS 27 CI. Device testing should include rapid direction changes with actual
artwork/transport controls to check native accessory geometry on iOS 27; simulator
placement assertions alone cannot establish that every animation frame is correct.


## Threshold reveal animation follow-up (2026-09-15)

The tester confirmed threshold reveal returns on iOS 27 but reported a snapping,
two-stage accessory expansion. The reveal state previously changed without an
explicit animation transaction, and MiniPlayerBar cleared animation whenever
native accessory placement changed. Scroll-idle could also restore the policy
before a reveal animation completed.

The reveal now requests one SwiftUI smooth animation, respecting Reduce Motion.
MiniPlayerBar inherits that transaction instead of suppressing it or adding a
separate curve. Hand-back requires both scroll-idle and SwiftUI animation
completion (`.removed`); new contacts cannot truncate an in-flight reveal and
reset invalidates stale completions. No UIKit geometry changes or timer were added.

Fourteen state/regression tests passed locally. The repeated reveal UI test now
waits for both expanded placement and completion/hand-back before starting its
next cycle; this passed on iOS 26.5. These checks verify lifecycle and placement,
not frame-by-frame smoothness on an iOS 27 device. The reported iOS 27 visual
artifact still needs confirmation against this build.


## iOS 27 native batch transition candidate (2026-09-15)

The tester reported no visual improvement from the SwiftUI animation change.
Final-placement assertions were insufficient evidence of animation quality.

`ThresholdTabBehavior` now selects one owner per platform: iOS 26 retains the
working SwiftUI modifier, while iOS 27 omits that modifier and installs a native
UIKit driver. The iOS 27 driver synchronously updates the reveal state and native
minimization policy inside `UITabBarController.performBatchUpdates`. Core Animation
completion gates hand-back along with scroll-idle. This tests Apple's documented
batching of tab changes into one animated layout pass; smooth accessory expansion
on iOS 27 is not yet established. Older SDK builds invoke the same public API by
its Objective-C selector after checking availability.

The local iOS 26.5 regression suite and repeated reveal UI test passed. CI now
records the iOS 27 reveal test to `ios27-reveal.mp4`, using an accessory whose
height/artwork/control layout changes with native placement. Review that recording
and the actual device before calling the visual issue fixed. No UIKit frame writes,
forced layout, fixed-duration hand-back timers, or custom tab-bar drawing are used.


## Native batch driver reverted after device regression (2026-09-15)

The tester reports that commit 78cae06 prevents downward-scroll minimization on
iOS 27. The native driver is removed and the SwiftUI minimization modifier is
restored on all iOS versions, returning production behavior to d7beb57. The
72-point reveal remains. The richer diagnostic accessory and CI recording remain
so future work can capture the unresolved iOS 27 upward animation artifact.

The previous local passing tests exercised only the iOS 26 path and did not
validate the new iOS 27 driver. Do not treat those results as evidence that the
iOS 27 regression was absent. The upward animation issue is still open.


## Instrumented reveal comparison (2026-09-15)

Four attempts have now changed the reveal without removing the iOS 27 symptom,
and none of them produced a measurement of what the transition actually does.
This round ships the measurement and the alternatives together, so one device
session can settle it instead of one rebuild per hypothesis.

**Diagnostic.** `TabRevealProbe` runs a `CADisplayLink` for ~0.9s from the moment
a reveal or hand-back is requested and records, per frame, the model frame and
the Core Animation *presentation* frame of `UITabBarController.tabBar` and of
every accessory-hosting view under the controller (matched by class name; only
`layer` is read, which every `UIView` has). Model and presentation frames differ
only while an animation is in flight, so a reveal that jumps produces a single
line where they already agree, while an animated one produces a ramp. Accessory
placement flips are written onto the same timeline from `MiniPlayerBar`. Output
goes through `DebugLogger`, which is a `UserDefaults` gate rather than `#if
DEBUG`, so a Release device build carries it; **Developer → Reveal Diagnostics**
plus **Debug Logging**, then **Export Debug Logs**.

**Strategies** (`TabRevealStrategy`, **Developer → Tab Bar Reveal**, default is
today's behaviour so nothing changes unless it is changed):

| Case | Who flips the policy |
| --- | --- |
| `declared` | SwiftUI declares `.never` for the length of the reveal. Shipping. |
| `uikitFlip` | Declaration stays constant at `.onScrollDown`; the controller's property is assigned directly. |
| `uikitAnimatedFlip` | As above, committed inside an explicit `UIView` animation and `performBatchUpdates`. |
| `declaredLateHandBack` | `declared`, but the policy is handed back at the next gesture rather than on scroll-idle. |

`uikitFlip` is not a new idea: it is what `TabBarMinimizeCoordinator` did before
4aff469, measured then on an iOS 26.5 device as one clean accessory move in
~54ms against the two-stage move the declared flip produced. The reason 78cae06
regressed downward minimization is that it *dropped* the SwiftUI modifier on the
iOS 27 path; the declared default then replaces `.onScrollDown` on the next
update pass. Every strategy here keeps a minimize behaviour declared at all
times, and the UIKit paths additionally leave `isRevealed` unpublished, because
publishing it is itself an update pass that can re-apply the declared value
inside the window where `.never` has to hold.

Validation: 313 unit tests pass on the local iOS 26.5 simulator, including three
new ones covering driver ownership, late hand-back, and driver removal. This is
lifecycle coverage. **No claim is made here that any of these fixes iOS 27** —
there is no iOS 27 SDK or runtime on the build host, so the comparison has to
happen on the device.


## Measured: the expansion is orphaned, not mis-flipped (2026-09-15)

Three strategies were run on the iOS 27 device and all three glitched
identically. The frame-by-frame logs say why: **none of them was ever the
variable.**

Seven reveal cycles across the three logs, times relative to the moment the
minimize animation started:

| Log | Strategy | Reveal requested | x/width arrives | y arrives |
| --- | --- | ---: | ---: | ---: |
| text.txt | `declared` | 914ms | 994ms | 1098ms |
| text.txt | `declared` | 762ms | 992ms | 1105ms |
| text.txt | `declared` | 936ms | 999ms | 1099ms |
| text 2.txt | `uikitFlip` | 816ms | 997ms | 1097ms |
| text 2.txt | `uikitFlip` | 824ms | 999ms | 1091ms |
| text 3.txt | `declaredLateHandBack` | 615ms | 989ms | 1102ms |
| text 3.txt | `declaredLateHandBack` | 652ms | 997ms | 1109ms |

The request lands anywhere between 615ms and 936ms; the bar always moves at
~995ms and ~1100ms. The arrival is locked to the minimize animation, not to the
reveal.

What one cycle looks like, with the accessory container's model frame against
its Core Animation presentation frame:

```
t= 10ms  model=(21,673,333,48)  pres=(90,735,194,48)   layout already expanded, screen still inline
t=218ms  model=(21,673,333,48)  pres=(90,736,195,48)   the old minimize spring, still settling 194→195
t=230ms  model=(21,673,333,48)  pres=(21,736,333,48)   full width, still at tab-bar height
t=331ms  model=(21,673,333,48)  pres=(21,736,333,48)
t=343ms  model=(21,673,333,48)  pres=(21,673,333,48)   above the tab bar
```

So iOS 27 applies the expansion's geometry immediately and attaches **no
animation to it**. The ~1s minimize animation is still on the layer, Core
Animation keeps presenting it, and the frame is held until it ends — then the
layer snaps to the model value in two steps, because the width and position
animations expire ~100ms apart. The variable dead time is the remainder of that
second, which is why it read as lag.

The same logs show the minimize animating correctly in ~25 interpolated samples
over ~470ms: it is driven by the scroll interaction, so UIKit animates it. Only
the policy-driven expansion is unanimated. No flip strategy can change that.

`TabRevealTransition` (strategy **UIKit flip, app animates the expansion**)
captures the accessory subtree's presentation frames, performs the flip, forces
the layout pass, and then animates each changed layer from where it actually was
on screen to where UIKit has put it, removing only the stale `position`/`bounds`
animations that would otherwise hold it. Views are found by class name and only
`layer` is read or animated; no frame is ever assigned, so UIKit remains the only
thing laying the accessory out.

The probe now also records a window whenever accessory placement changes with
nothing else recording, which catches UIKit's own long-distance reveal — the one
case still unmeasured, and the one that says whether a reveal with no stale
animation in flight animates at all. Each frame line now also carries the running
animations on each layer with their durations.

316 unit tests pass locally on iOS 26.5. The fix itself is an iOS 27 claim that
this host cannot check; it needs the device.


## Correction: the expansion is never animated (2026-09-15)

Device run on strategy 3 (`declaredLateHandBack`), with the probe now recording
placement-triggered windows and each layer's running animations.

**The settled case.** Minimize, wait ~2s, then scroll up — reported as "appears
above the bar without any animation and without glitch", and the frames agree:

```
t= 10ms  model=(21,673,333,48)  pres=(21,736,333,48)
t= 80ms  model=(21,673,333,48)  pres=(21,673,333,48)
```

One step, no ramp. So iOS 27 does not animate a policy-driven expansion **at
all**; the glitch is what that looks like when a minimize is still resolving,
not a separate failure.

**The animation introspection is the surprise.** Every probe window logs
`anim bar[-] acc0[-] acc1[-]` from its first frame to its last: the tab bar, the
accessory container and its host carry **no `CAAnimation`s** while the
presentation frame disagrees with the model for hundreds of milliseconds. This
corrects the previous section, which said the stale minimize animation was still
on the layer — it is not; those values come from somewhere not reachable as a
local animation. Removing animations therefore cannot fix this by itself, and
`TabRevealTransition`'s removal step is only insurance. What can fix it is
supplying a real animation on the layer, which is what that type does.

The probe also caught the inner host's presentation at `(69,0,194,48)` against a
model of `(0,0,333,48)` mid-glitch — the contents sitting offset inside the
container, which is the "shortly behind the menu bar" flash.

Still untested on the device: strategy **UIKit flip, app animates the
expansion**. It is the only one that adds a transition rather than choosing who
asks for it, and on this evidence it is the only one that can.


## The native reveal does animate (2026-09-15)

The `adoptedTransition` strategy failed on the device — nothing animated and the
tab bar stopped responding to scrolling entirely. Two defects, both mine:

- The reveal's completion was a `CATransaction` completion block. `.never` stays
  set and the state machine stays mid-reveal until that block runs, so a
  transaction that registers no animation — which is exactly what happens when
  the layers carry none — leaves the policy latched at `.never` forever. The tab
  bar can then never minimize again, which is the reported symptom. Completion is
  now a plain main-actor timer, which cannot be starved, and the spring's
  duration is capped instead of taken from `settlingDuration`.
- `controller.view.layoutIfNeeded()` ran a whole tab-controller layout from
  inside the scroll callback that asked for the reveal. The animation is now
  applied a runloop turn later, off UIKit's update.

**The find is in the same log.** At 6:20:29.601 the probe caught an expansion it
did not cause, with `mode=onScrollDown` — UIKit's own scroll-driven reveal:

```
t= 4ms  pres=(90,736,195,48)
t=27ms  pres=(90,733,195,48)
t=51ms  pres=(90,721,195,48)
t=19ms  pres=(87,707,200,48)   (continues under the next probe window)
t=44ms  pres=(77,693,220,48)
t=94ms  pres=(55,678,264,48)
t=152ms pres=(28,670,317,48)
t=211ms pres=(19,671,335,48)
```

x, y and width moving together over ~200ms, with a slight overshoot — a proper
transition. Our 72-point flip fired 57ms into it and did not disturb it.

So iOS 27 has not lost the animation. It animates the expansion the scroll
interaction drives, and does not animate one a policy change asks for. No flip
strategy can cross that gap, because the flip is the thing that is not animated.

`nativeOnly` declares `.onScrollDown` permanently, installs no bridge, and leaves
the scroll views unobserved so nothing can request a reveal. The trade is Apple's
reveal distance for our 72 points, which is the same trade the follow-up above
made deliberately — but this time with a measurement showing what is bought with
it. 316 unit tests pass locally.


## Reveal speed and the overtaking snap (2026-09-15)

Device results on the fixed build: `nativeOnly` animates correctly and never
glitches, but UIKit's own reveal on iOS 27 only fires **at the top of the scroll
view**, not at a shorter distance — so it cannot carry the feature on its own.
`adoptedTransition` now animates, but read as too slow and could still flash the
accessory above the tab bar.

Two changes, both aimed at what was reported:

- **0.45s → 0.22s**, matched to the ~200ms ramp measured on UIKit's own reveal.
  That also halves how long `.never` is held, which shortens the window in which
  anything else can go wrong.
- **`TabRevealSettler`.** The reveal was treating its own animation's end as the
  end of the transition. It is not: a reveal asked for during a minimize gets
  overtaken about a second after that minimize began, when whatever drives those
  presentation values resolves and snaps the accessory to the model frame. With
  a 0.45s animation that snap landed after the animation was over and read as a
  jump. The settler watches the accessory layers for the rest of that window and
  answers a snap with a 120ms animation from wherever the layer actually is, so
  it glides instead. It skips any layer whose reveal animation is still running,
  ignores sub-pixel drift, and stops once the window has passed.

316 unit tests pass locally. Both changes are device-visible claims that this
host cannot check.


## Isolating the cause: the control was never run on iOS 27 (2026-09-17)

Every measurement in this document was taken inside the real shell, so all of it
is about "iOS 27 plus this app" and none of it can say which half is
responsible. The control for that — a bare tab bar with a bare accessory and
none of this app around it — has existed since ae04c3e as `NativeTabRevealProbe`,
behind `#if DEBUG` and a launch argument. **Device builds of this project are
Release**, so it was compiled out of every build that ever reached an iOS 27
device; its only recorded result is from the iOS 26.5 simulator. That is the gap.

It is now `IsolatedTabRevealProbe`, Release-compiled and reachable from
**Developer → Tab Bar Reveal → Isolated Tab Bar**. It runs whichever strategy the
developer menu has selected, so the comparison is like for like. It contains a
`TabView`, three tabs, a `NavigationStack`, a plain `ScrollView` and an accessory
made of two `Image`s and a `Text` — and none of:

| Suspect | What it does to the accessory or the bar |
| --- | --- |
| `MiniPlayerTouchRegion` | two `UIView`s hosted inside the accessory content |
| `MiniPlayerGesture` | a window-level `UIGestureRecognizer` that answers `false` to both `canBePrevented(by:)` and `canPrevent(_:)` |
| `onGeometryChange` reporting | writes the accessory's frame to two observable singletons on every frame of its movement |
| `MarqueeText` | runs its own animations inside the accessory |
| `NowPlayingOverlay` | a sibling of the whole shell in a `ZStack` |
| `TabSearchProminenceInstaller` | the only iOS-27-only code we have that touches the tab bar controller |

**The prominence installer is already partly ruled out by the existing logs.** It
writes `prominentTabIdentifier` only when its read-back differs from the value it
wants, and it logs every write. The device log contains exactly two of those
lines, both within 156ms of launch, and none across the following two minutes of
scrolling — so it is quiet during the transitions, whatever else is true of it.
Worth recording separately: the second line reports `previous=nil` 156ms after
the first one assigned the identifier, so the property did not read back what was
written to it.

No production behaviour changed; the default strategy still reproduces the
committed one exactly. 316 unit tests pass locally.


## Root cause: it is not this app (2026-09-17)

`IsolatedTabRevealProbe` — a bare `TabView`, three tabs, a plain `ScrollView` and
an accessory of two `Image`s and a `Text`, with no mini player, no window
gesture, no touch regions, no Shimeji, no player overlay and no prominence
installer — **glitches 1:1 identically to the real app on iOS 27**. Every suspect
in the table above is ruled out at once. The defect is in iOS 27's handling of
`tabBarMinimizeBehavior`, and no change to this app's tab bar, mini player or
accessory can fix it.

Stated precisely, from the frame-by-frame measurements:

> On iOS 27, force-expanding the tab bar by setting `tabBarMinimizeBehavior` to
> `.never` applies the expanded geometry with **no transition of any kind**. If a
> minimize is still resolving, the expansion is additionally *held* until that
> resolves — ~995ms after the minimize began, independent of when the expansion
> was requested — and then applied in two jumps ~100ms apart. UIKit's own
> scroll-driven reveal, by contrast, animates correctly (~200ms, all axes
> together). The interaction animates; the policy change does not.

### What ships

`TabRevealStrategy.automatic`, now the default:

- **iOS 26** keeps the declared 72-point threshold reveal. It animates correctly
  there and the tester confirms it is fine.
- **iOS 27** takes `nativeOnly`: `.onScrollDown` declared and never changed, no
  bridge, scroll views unobserved. Confirmed on device as animated and
  glitch-free. The cost is that iOS 27's native reveal fires only at the top of
  the scroll view, so there is no short reveal on that OS.

The other five strategies stay reachable from Developer for re-testing when a new
iOS 27 build lands; they are the record of what was ruled out.

### Worth filing with Apple

`IsolatedTabRevealProbe` is already a minimal reproducer and can be lifted into a
sample project close to as-is: set `.tabBarMinimizeBehavior(.never)` on a
`TabView` with a `tabViewBottomAccessory` after a short upward scroll, on iOS 27,
and compare against iOS 26.

316 unit tests pass locally.
