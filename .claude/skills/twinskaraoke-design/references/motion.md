# Motion: springs, transitions, perpetual animation

Everything lives in `Packages/UI/Animations/Apple/AppMotion.swift` (shared by
every app) plus `withOptionalAnimation` in
`Apps/iOS/Components/Shared/AppTheme.swift`.

## The spring scale: pick by role

One physics family, so every interaction feels tuned by the same hand.

| Token | Spring | Use for |
| --- | --- | --- |
| `AppMotion.snap` | response 0.22, damping 0.88 | small state flips: icons, badges, toggles, selection |
| `AppMotion.quick` | 0.32 / 0.85 | the default: row and list changes, control state, chrome reveals |
| `AppMotion.standard` | 0.42 / 0.84 | content moves: section reflows, layout swaps, sheet content |
| `AppMotion.gentle` | 0.58 / 0.85 | large surfaces: hero artwork, full-screen layout shifts, lyric scrolling |
| `AppMotion.playful` | 0.34 / 0.70 | rare celebratory moments only |
| `AppMotion.crossFade` | ease-in-out 0.25 | the Reduce Motion replacement for a move or morph |

- A new `.spring(...)`, `.easeInOut(...)` or duration literal at a call site
  needs a reason in the plan. If none of the roles fits, propose a new role in
  `AppMotion` rather than a one-off.
- Don't retune a role to fix one screen; every call site inherits it.
- `AppMotion.spring/easeInOut/easeOut/linear(duration:)` exist for the few
  places that need an explicit curve (a progress bar, a loop). They clamp
  negative durations.

## Reduce Motion and reduced effects

Two environment flags, injected once at each app root by
`injectReduceMotion()`:

- `@Environment(\.appReduceMotion)`: the system Reduce Motion setting,
  unless the user switched off "respect reduced motion" in the app. Use it for
  **interaction transitions**: remove the movement itself (a change of
  position, size or scale, a matched-geometry morph, a sliding transition)
  and fade instead. `AppMotion.crossFade` is only the timing curve for that
  fade; on its own it still animates any movement.
- `@Environment(\.appReduceEffects)`: Reduce Motion **or** Low Power Mode
  **or** thermal state `.serious`/`.critical`. Use it for **perpetual
  decoration** only (equalizer, shimmer, ambient backdrop, pulses, marquee).
  Gating an interaction transition on it would make the whole UI feel broken
  in Low Power Mode.

Don't read `accessibilityReduceMotion` directly in a view; it ignores the
in-app preference.

The usual shape: under Reduce Motion, both the transition and the timing
change, and anything matched or moving is switched off.

```swift
@Environment(\.appReduceMotion) private var reduceMotion

var body: some View {
    if isExpanded {
        DetailPanel()
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}

func toggle() {
    withOptionalAnimation(reduceMotion ? AppMotion.crossFade : AppMotion.standard) {
        isExpanded.toggle()
    }
}
```

`PlayerSurfaceMorph` (`Apps/iOS/Screens/Player/PlayerSurfaceMorph.swift`) is
the full version: its `.crossFade` style turns off the matched geometry,
keeps `.opacity` transitions and uses `AppMotion.crossFade`.

`withOptionalAnimation(nil) { … }` applies the change without an animation.

## Perpetual decorative animation: `ActiveAnimationClock`

New always-moving decoration is a `TimelineView` that samples an
`ActiveAnimationClock`, **not** `withAnimation(… .repeatForever)`. The clock
banks elapsed time only while running, so an effect paused by scrolling, by
the app leaving the foreground or by `onDisappear` resumes in phase instead
of snapping back to its start. `EqualizerBars` is the reference
implementation:

```swift
@Environment(\.appReduceEffects) private var reduceEffects
@Environment(\.scenePhase) private var scenePhase
@State private var animationClock = ActiveAnimationClock()
@State private var isVisible = false

var body: some View {
    TimelineView(.animation(
        minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
        paused: !shouldAnimate
    )) { context in
        let elapsed = animationClock.elapsed(at: context.date)
        // draw from `elapsed`, ideally into a Canvas so a tick doesn't relayout rows
    }
    .onAppear { isVisible = true }
    .onDisappear {
        isVisible = false
        animationClock.setRunning(false, at: .now)
    }
    .onChange(of: shouldAnimate, initial: true) { _, running in
        animationClock.setRunning(running, at: .now)
    }
}

private var shouldAnimate: Bool {
    isVisible && !reduceEffects && scenePhase == .active
        && !ScrollPerformanceState.shared.isScrolling
}
```

- The clock is a **class** held in `@State` on purpose. As a struct, a view
  inserted while it should already be animating lost the start write and sat
  frozen. Don't "simplify" it to a struct.
- `DisplayRefreshRate.decorativeAnimationInterval` (60 fps) for ambience;
  `lightweightAnimationInterval` (full ProMotion rate) only for small,
  constantly-moving elements like spinners and bouncing dots.
- Pause while scrolling (`ScrollPerformanceState.shared.isScrolling`) and,
  for effects in lists the full-screen player covers, while
  `NowPlayingPresentation.shared.isExpanded`.
- Adopters: `EqualizerBars`, `PlayerAmbientBackground`,
  `PulsingMusicEmptyStateMark` (`RemoteArtworkImage.swift`), `RadioLiveDot`
  (`RadioPlayerLayout.swift`). `MarqueeText` uses the same `TimelineView`
  shape with a pure `phase(elapsed:…)` function.

**Leave the remaining `repeatForever` sites alone.**
`AuroraBackgroundViews` and `QRApproveView`'s pulses animate plain animatable
properties through a scoped animation, which Core Animation runs off the main
thread and suspends in the background for free. (The watch and TV apps have
their own `repeatForever` uses; the clock is an iOS pattern.) Rewriting
them as a 60 fps `TimelineView` moves per-frame work back onto the CPU, which
makes them slower. The clock earns its cost where a `Canvas` is redrawn, where
a live `repeatForever` transaction would leak into unrelated layout changes,
or where the effect must survive a pause in phase.

## Transitions and navigation

- `ZoomNavigationLink` (`Apps/iOS/Components/Shared/ZoomNavigationLink.swift`)
  is the Apple Music "artwork lifts out of the tile" push. Use it only where
  label and destination share artwork. Its `@Namespace` must be declared on
  the view that owns the `ForEach` (or higher), never inside a lazy cell. Read
  its doc comment before touching it; navigation changes need approval.
- Prefer system transitions (`navigationTransition(.zoom)`,
  `matchedTransitionSource`, `contentTransition(.numericText())`,
  `.symbolEffect`) over hand-rolled `matchedGeometryEffect` morphs when the
  user can interrupt the motion: a custom morph can't be dragged back.
- Text or numbers that change in place: `contentTransition`, inside an
  animation from the scale above.

## Gradients

SwiftUI gradients interpolate perceptually by default. Between two saturated
theme colours (cyan → pink) that passes through a grey lavender. To match the
website's CSS, use `Gradient(colors: …).colorSpace(.device)`. A gradient
`.tint` on a `Slider` is flattened to its first colour.

## Apple guidance worth fetching (Sosumi)

Search Sosumi by title, then fetch the result by path:

- HIG: *Motion*, *Playing haptics*, *Materials*, *Accessibility*.
- WWDC23: *Explore SwiftUI animation*, *Animate with springs*, *Wind your way
  through advanced animations in SwiftUI*.
- WWDC25: *Meet Liquid Glass*, *Build a SwiftUI app with the new design*.

Apple's examples use raw springs and colours; map them onto the roles and
tokens here.
