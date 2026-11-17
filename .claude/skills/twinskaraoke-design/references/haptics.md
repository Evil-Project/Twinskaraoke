# Haptics

`Packages/UI/Accessibility/Apple/AppHaptic.swift` (the engine is iOS-only;
`play()` does nothing on other platforms). Press feedback is
`PressableButtonStyle(haptic:)` in `Packages/UI/Components/Apple/`.

## Roles, not textures

Pick the role for **what happened**, never for the strength you want. The
texture behind a role is tuned once in `HapticEngine` and every call site
inherits it.

| Role | Meaning |
| --- | --- |
| `.selection` | a discrete selection moved: row tap, tab change, segment, filter, picker step (the most common) |
| `.detent` | a continuous drag crossed a notch: scrub detents, reorder steps (rate-limited) |
| `.grab` | something was picked up: drag begins, long-press arms |
| `.commit` | a control committed to its action: primary button, play/pause, send |
| `.dismiss` | the gentle counterpart: a surface closed, an action cancelled, a setting turned off, a deletion the user asked for |
| `.boundary` | travel hit a limit: scrub end-stop, list edge, cap reached |
| `.success` | the work finished and it went well |
| `.warning` | the work finished but **needs attention**: blocked input, failed validation |
| `.error` | the work failed |
| `.celebrate` | a rare earned moment (CoreHaptics pattern) |

Rationed on purpose:

- `.warning` is not "the user deleted something". A destructive action the
  user commanded plays `.dismiss` when it happens, or `.selection` when it only
  opens a confirmation.
- `.celebrate` fires from exactly one place: a finished download batch of more
  than one song (`DownloadManager`). Adding a second use makes both feel
  cheap; ask first.

## Wiring

- A `Button` with an action: play the role in the action, or set it on the
  style: `PressableButtonStyle(haptic: .commit)`. **Never both**; it fires
  twice and reads as a stutter. When the action plays one, pass
  `haptic: nil` to the style (see `SongRow` and `AddToPlaylistSheet`).
- No action closure: `toggleHaptic(_:)` on a `Toggle`'s bound value (commit on,
  dismiss off), `selectionHaptic(_:)` on a `Picker`'s selection. Don't add
  another `onChange` for this, and don't add `toggleHaptic` where the binding's
  setter already plays one.
- Inside a `ToolbarItem`, SwiftUI substitutes its own button style and drops
  the custom style's haptic. Play it from the action instead.
- `AppHaptic.<role>.prepare()` at the start of a gesture removes the first-tap
  latency.
- `play()` checks the user's Haptics setting itself (`nk.hapticsEnabled`);
  call sites never check it.

## Don't

- Don't create a `UIFeedbackGenerator` or `CHHapticEngine` at a call site; go
  through `AppHaptic`. The engine shares the app's audio session on purpose
  (a separate one would fight playback).
- Don't add a path in `HapticEngine` that skips `playImpact`: it enforces the
  global rate floor that keeps the system's 32 Hz haptic limit from dropping
  feedback during scrubs.
- Don't retune intensities, rungs or the detent spacing without printing the
  role × strength matrix and checking for collisions, and without a device.
- CoreHaptics `stoppedHandler` / `resetHandler` closures stay `@Sendable`:
  they run off the main queue, and with MainActor default isolation they would
  otherwise trap at runtime with no compiler warning.

## Verification

The simulator has no Taptic Engine. Every haptic change needs a device check;
say so in the PR. If a "haptics rate limit" log appears, first switch Haptics
off in Settings and repeat: if the log stays, it isn't ours (the system volume
slider produces the same message).
