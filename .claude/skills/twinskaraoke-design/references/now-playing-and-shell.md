# Now Playing presentation and the app shell

**Changing anything here needs approval first** (AGENTS.md: playback and
navigation). The files carry long doc comments recording what was measured on
device; read them before proposing a change. Don't grow
`FullScreenPlayerView.swift` or `ContentView.swift`; extract a new type.

## Shape

Files: `Apps/iOS/Screens/Player/NowPlaying/`.

- **Mini player:** `MiniPlayerBar` inside `tabViewBottomAccessory(isEnabled:)`.
  The system supplies the glass, the merge with the minimized tab bar and the
  bottom content inset. It reads `\.tabViewBottomAccessoryPlacement`
  (`.inline`, `.expanded`, or nil in the iPad sidebar, where the same view is
  used in a `safeAreaBar`). Design it for all three.
- **Full-screen player:** `NowPlayingOverlay`, a sibling of the app shell.
  It stays mounted whenever there is a song and is parked off-screen when
  closed, so player state (lyrics, queue sheet) survives closing. Don't
  unmount it on close.
- **One scalar drives the presentation:** `NowPlayingPresentation.progress`.
  New player chrome reads it instead of keeping its own open/closed state.
- **Artwork morph:** `ArtworkMorphLayer` flies the artwork between the bar and
  the player, landing on `AM.Radius.hero` (see `design-system.md`).

## Traps that are already solved

- **Dismissal has one rule:** `PlayerDismissMetrics.shouldDismiss` dismisses
  when the projected end of the drag passes a quarter of the player's height.
  Don't add a distance clause back: for a drag still moving down it can never
  decide anything the projection hasn't, and it only fires on a drag heading
  back up, which should cancel.
- **Gesture precedence:** child gestures (scrubber, lyrics and queue scrolling)
  win over the dismissal drag by design, as in Apple Music. Don't attach the
  dismissal as `simultaneousGesture` (drags the player while seeking) or
  `highPriorityGesture` (steals the scrubber).
- **Report-and-clear geometry needs an owner.** A view that reports its frame
  in `onGeometryChange` and clears it in `onDisappear` must pass an owner token
  if it can be replaced in place (`.id(song.id)`, a rehosted accessory). The
  new view reports before the old one's `onDisappear` runs; without an owner
  the clear wins and the morph silently falls back to a plain slide.
- **Tab bar minimizing:** `.tabBarMinimizeBehavior(.onScrollDown)` is declared
  in `ContentView`. There is no public API for the reveal threshold or the
  minimized state. On iOS 27 the forced reveal isn't animated; that is Apple's
  behaviour, proven with an isolated probe. Don't go hunting for it in the
  shell.

## Other SwiftUI traps from this codebase

- **Clipping inside an overlay:** an overlay is proposed its host's size, but
  a flexible frame inside it can still come out wider than the host. In
  `MarqueeText`, `.frame(maxWidth: .infinity)` in an overlay came out
  unbounded rather than the row's width, so the following `.clipped()` clipped nothing and the
  title drew over its neighbours. When content overflows an overlay, check the
  frame it actually got, then clip against a measured width
  (`onGeometryChange`). To tell a wrong frame from drawing that escapes a
  correct frame, add a temporary `.border(.red)`.
- **Menu item subtitles:** the subtitle must be a second `Text` directly in
  the `Button`'s label (`Label(…)` then `Text(…)`). Put inside `Label`'s title,
  it is silently dropped. A disabled item keeps its subtitle, which works for
  "unavailable because…".
- **`onScrollGeometryChange`:** return a coarse `Equatable` (an enum of zones)
  from the transform, never a continuously varying `CGFloat`, or the action
  runs every frame. Edge detection needs hysteresis; a rubber-band bounce
  oscillates across a plain threshold.
