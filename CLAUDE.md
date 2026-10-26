# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native Swift/SwiftUI client for [twinskaraoke.com](https://neurokaraoke.com) (formerly neurokaraoke), shipping an iPhone/iPad app and a companion Apple Watch app from a single Xcode project. There is no Package.swift, Podfile, or workspace — only `Twinskaraoke.xcodeproj` with SPM dependencies (`SDWebImageSwiftUI`, `LNPopupUI`) declared as `XCRemoteSwiftPackageReference`s inside the project file.

Bundle identifiers are `org.evilneuro.Twinskaraoke` for the iOS app and `org.evilneuro.Twinskaraoke.watchkitapp` for the watch. The README's user-facing instructions reference older `com.xiaoyuan151.*` IDs — trust the project file, not the README, for current values.

## Build & test

The two shared schemes are `Twinskaraoke` (iOS) and `TwinskaraokeWatchApp` (the watch target's product is named `Twinskaraoke Watch App.app`).

```bash
# iOS unsigned archive (matches what CI does in .github/workflows/build.yaml)
xcodebuild archive \
  -project Twinskaraoke.xcodeproj -scheme Twinskaraoke \
  -archivePath build/iPhone.xcarchive -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Watch unsigned archive
xcodebuild archive \
  -project Twinskaraoke.xcodeproj -scheme TwinskaraokeWatchApp \
  -archivePath build/Watch.xcarchive -destination "generic/platform=watchOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Run all iOS tests on a simulator
xcodebuild test -project Twinskaraoke.xcodeproj -scheme Twinskaraoke \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Run a single Swift Testing test by name
xcodebuild test -project Twinskaraoke.xcodeproj -scheme Twinskaraoke \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:TwinskaraokeTests/SongModelTests/songImageURL_withCloudflareId
```

Unit tests under `TwinskaraokeTests/` and `TwinskaraokeWatchAppTests/` use the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`) — not XCTest. The UI test targets (`TwinskaraokeUITests`, `TwinskaraokeWatchAppUITests`) still use XCTest.

## Architecture

### Two apps, deliberately duplicated

`Twinskaraoke/` and `TwinskaraokeWatchApp/` are independent targets with **no shared sources**. Files like `Models/Song.swift`, `Models/GuestIdentity.swift`, and `Services/StorageHost.swift` exist in both trees and must be kept in sync by hand when changing model shapes or storage hosts. Each app has its own audio singleton (`AudioPlayerManager.shared` on iOS, `AudioManager.shared` on watchOS) — they do not communicate.

### iOS shell (`Twinskaraoke/App/ContentView.swift`)

Root is a five-tab `TabView` (Home / Radio / Library / Search / Account). The mini-player and full-screen player are not regular SwiftUI views — they're rendered through `LNPopupUI`. The popup bar appears whenever `AudioPlayerManager.shared.currentSong != nil`; tapping it presents `FullScreenPlayerView`. Trailing controls in the popup bar swap between skip and stop based on `isRadioMode`.

### Audio pipeline (`Services/AudioPlayerManager.swift`)

Single `ObservableObject` singleton (~900 lines) that owns everything playback-related:

- **AVPlayer** lifecycle, time observation, remote command center, lock-screen now-playing info, AirPlay route tracking.
- **Caching**: progressive download via the nested `AudioDownloadSession` (a `URLSessionDataDelegate` that streams to `AudioCache/<songID>.mp3` while playing). `DownloadManager` handles the separate "permanently downloaded" tier; `play()` checks downloaded → cached → remote in that order.
- **Crossfade vs Auto-Mix**: two mutually exclusive transition modes. Setting either's `@Published` flag clears the other in `didSet`. Crossfade uses a second `AVPlayer` (`crossfadePlayer`) and timed volume ramps; auto-mix is a shorter ~2.5s fade. Both are gated by `scheduleAutoMixIfNeeded()`.
- **Karaoke / bass effects**: applied via `KaraokeAudioProcessor.attachTap(to:)`, which installs an `MTAudioProcessingTap` (`Services/KaraokeAudioProcessor.swift`) on the current `AVPlayerItem`'s audio mix. The processor uses **module-level static state** for the tap's format and filter coefficients — only one effect can be active at a time, and toggling `karaokeMode` and `bassEnhanceMode` is mutually exclusive (each clears the other in `didSet`). When changing effect logic, remember the tap callback runs on a real-time audio thread and must not allocate or call Swift runtime.
- **Radio mode**: `RadioController` (`Services/RadioController.swift`) polls `radio.twinskaraoke.com/api/nowplaying_static/neuro_21.json` every 15s. When the user starts the live stream, `AudioPlayerManager.playRadio(...)` switches into `isRadioMode`, which disables queue navigation and changes the play/pause control to play/stop.

### Region-aware backend (`Services/StorageHost.swift`)

All asset URLs are built through `StorageHost.base` and `StorageHost.images`, which switch between `*.neurokaraoke.com` and `*.neurokaraoke.com.cn` based on `Locale.current.region`. The override key `UserDefaults.standard.string(forKey: "nk.storageRegion")` (`"cn"` / anything else) takes precedence — useful for testing the China CDN. **Never hardcode storage/image hosts in new code.**

### Auth (`Services/AuthManager.swift`)

Two flows feed the same persisted token: native username/password POST to `api.neurokaraoke.com/api/auth/login`, and Discord OAuth via `ASWebAuthenticationSession` exchanging the code at `idk.neurokaraoke.com/api/auth/discord-token`. The custom URL scheme is `neurokaraoke://auth`. All state is persisted under `UserDefaults` keys prefixed `nk.` (`nk.token`, `nk.userId`, `nk.username`, `nk.avatar`); the same `nk.` prefix convention is used throughout the app for any user preference.

### Conventions worth keeping

- Singletons are pervasive (`AudioPlayerManager.shared`, `RadioController.shared`, `DownloadManager.shared`, `FavoritesManager`, etc.) and injected as `@EnvironmentObject` from `ContentView`. New cross-feature state should follow the same pattern rather than introducing a DI container.
- `Song.imageURL` and `Song.audioURL` are the only sanctioned ways to derive media URLs from a `Song` — they handle the Cloudflare-vs-path fallback and the leading-slash quirk in `absolutePath`.
- View files live under `Features/<Area>/` and are organized by tab; reusable presentation lives in `Components/`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
