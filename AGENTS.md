# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Working rules

- Perform requested fixes directly. Do not generate audit logs, audit reports, or audit-report files unless the user explicitly asks for one.
- Preserve existing APIs, persisted data formats, backend schemas, and business logic while refactoring.
- Preserve unrelated working-tree changes.

## Project

Native Swift/SwiftUI clients for twinskaraoke.com: iOS/iPadOS, watchOS, macOS, tvOS, and widget extensions, built from `Twinskaraoke.xcodeproj`. Local sources under `Packages/` are synchronized Xcode source groups, not separate Swift packages. External SPM dependencies are declared in the project file; trust it for bundle identifiers and target membership.

## Product goal

- Treat the app goal as: **make an Apple Music-like app**.
- For future UI, UX, and copy decisions in this repository, prefer Apple Music-like structure, wording, spacing, hierarchy, and interaction patterns unless the user explicitly asks for a different direction.

## Build & test

Shared schemes include `Twinskaraoke`, `TwinskaraokeWatchApp`, `Twinskaraoke Mac App`, and `Twinskaraoke TV App`. Resolve an available simulator UDID before running tests.

```bash
# iOS unsigned archive (matches what CI does in .github/workflows/build-ipa.yml)
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
  -destination 'platform=iOS Simulator,id=<available-iPhone-UDID>'

# Run a single Swift Testing test by name
xcodebuild test -project Twinskaraoke.xcodeproj -scheme Twinskaraoke \
  -destination 'platform=iOS Simulator,id=<available-iPhone-UDID>' \
  -only-testing:TwinskaraokeTests/SongModelTests/songImageURL_withCloudflareId
```

Unit tests under `Tests/UnitTests/iOS/` and `Tests/UnitTests/watchOS/` use the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`) — not XCTest. The UI test targets (`TwinskaraokeUITests`, `TwinskaraokeWatchAppUITests`) still use XCTest.

## Architecture

### Source boundaries

- `Apps/<platform>/`: entry points, navigation, screens, presentation components, and application wiring.
- `Packages/Domain/Models/Apple/`: shared data models and decoding contracts. Keep networking and platform effects out of model definitions; compatible convenience properties may live in extensions in infrastructure/feature sources.
- `Packages/Core/`: configuration, authentication, networking, security, logging, and storage.
- `Packages/Data/`: shared repositories, endpoint contracts and response caches, built on Core and Domain.
- `Packages/Features/`: feature state, account facades and behavior, with platform-specific adapters where needed.
- `Packages/Platform/`: WatchConnectivity (including `WatchCompanionSession`, exposed as `WatchAuthManager` for compatibility), widgets, intents, CarPlay, and other system adapters.
- `Packages/UI/`: reusable appearance, interaction, and animation code.
- `Extensions/`: widget entry points and shared extension contracts.

Keep shared rules in shared sources rather than duplicating them across targets. Preserve platform-specific playback and lifecycle behavior. Wire cross-feature effects at the application boundary; avoid dependencies from storage to playback/UI or from playback to concrete platform publishers. Existing singleton facades remain supported; do not introduce a DI container.

### Playback and presentation

The iOS `AuthManager.shared` is initialized at app startup and owns the session beyond screen lifetimes. `AppServices` wires its account effects and the playback/platform adapters. The iOS `AudioPlayerManager.shared` is the observable playback facade. Local playback uses `AVEnginePlayback`; streaming and radio use AVPlayer. The custom Now Playing presentation lives under `Apps/iOS/Screens/Player/NowPlaying/`. Preserve queue/repeat/autoplay policy, mutually exclusive effects and transitions, permanent-download → cache → remote source selection, background recovery, and cancellation generations. Never allocate or call the Swift runtime from real-time audio callbacks.

Phone and watch coordinate account and playback ownership through WatchConnectivity. Preserve companion payload keys, lease epochs, revisions, account generations, deduplication, and single-owner handoff behavior.

### Backend and persistence

Use `StorageHost` for region-aware storage, images, API, and identity endpoints; never hardcode new storage/image hosts. The `nk.storageRegion` preference overrides locale selection. Existing `Song.imageURL` / `Song.audioURL` accessors remain the supported media URL entry points.

Authentication supports native login, Discord OAuth, and companion/QR flows. Tokens are stored through `CredentialStore` in Keychain. Preserve existing Keychain identifiers, `nk.` preference keys, commit markers, URL schemes, and protected-data restoration behavior. Keep Codable keys, cache/download directories, manifests, and widget/companion formats backward compatible.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
