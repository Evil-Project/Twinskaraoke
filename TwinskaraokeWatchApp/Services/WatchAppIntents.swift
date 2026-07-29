import AppIntents
import Foundation

/// Siri and Shortcuts entry points.
///
/// These conform to `AudioPlaybackIntent` rather than plain `AppIntent` so the
/// system lets them start audio without bringing the app to the front — the
/// point of asking a watch to play something is not having to look at it.
struct PlayLiveRadioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Radio"
    static let description = IntentDescription(
        "Starts the live Twinskaraoke station on this watch."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        let radio = RadioController.shared
        // Awaited rather than left to `playLiveStream`'s own retry, so the
        // intent doesn't report success before the station is known.
        if radio.nowPlaying == nil {
            await radio.refresh()
        }
        radio.playLiveStream()
        return .result()
    }
}

struct ResumePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume Playback"
    static let description = IntentDescription(
        "Plays or pauses whatever is loaded on this watch."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = AudioManager.shared.togglePlayPause()
        return .result()
    }
}

/// Skipping is meaningless on a live stream, so this one is an ordinary
/// `AppIntent`: it changes what is queued rather than starting audio.
struct PlayNextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Next Track"
    static let description = IntentDescription(
        "Skips to the next song in the queue on this watch."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioManager.shared.playNext()
        return .result()
    }
}

struct TwinskaraokeWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLiveRadioIntent(),
            phrases: [
                "Play \(.applicationName) radio",
                "Listen to \(.applicationName) radio",
                "Start \(.applicationName) radio",
            ],
            shortTitle: "Play Radio",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Pause \(.applicationName)",
            ],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: PlayNextTrackIntent(),
            phrases: [
                "Skip this song in \(.applicationName)",
                "Next track in \(.applicationName)",
            ],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
    }
}
