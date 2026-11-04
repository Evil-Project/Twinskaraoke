# AGENTS.md — Playback

Playback is the most regression-prone area of the app. These rules add to the
root `AGENTS.md`.

- Always plan first and get approval before changing anything in this folder.
- Platform managers: iOS `AudioPlayerManager` (+ `AVEnginePlayback`,
  `AudioSessionController`, `NowPlayingPublisher`, `TransitionCoordinator`,
  `VocalSeparator`), watchOS `AudioManager`, tvOS `AudioManager`, macOS
  `MacAudioManager`. A behavior change on one platform usually needs the same
  change, or an explicit "not applicable", on the others.
- `AudioPlayerManager.swift` is over 4,000 lines. Don't add to it. New logic
  goes into a focused type in its own file that the manager calls.
- Keep `RepeatMode` raw values and the session/snapshot formats stable: saved
  sessions, widget snapshots and Watch sync decode them.
- Audio session, interruption and media-services-reset handling live in
  `AudioSessionController`. Keep resume intent accurate after interruptions.
- No blocking I/O or network on the main actor. Reuse the shared `URLSession`
  for streamed and predownloaded songs.
- Required tests for any change here: the matching file in
  `Tests/UnitTests/iOS/` (`AVEnginePlaybackRegressionTests`,
  `AudioSessionControllerTests`, `PlaybackLoadFailureTests`,
  `NowPlayingInfoBuilderTests`, `SleepTimerTests`, …) or
  `Tests/UnitTests/watchOS/` (`WatchPlaybackRegressionTests`,
  `CompanionPlaybackTests`, …).
- Manually check on a device or simulator: lock screen controls, an
  interruption (call/Siri), AirPlay/Bluetooth route change, and relaunch
  restore. List what you checked in the PR.
