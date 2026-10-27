import AppIntents
import Foundation

/// Siri and Shortcuts entry points.
///
/// These conform to `AudioPlaybackIntent` rather than plain `AppIntent` so the
/// system lets them start audio without bringing the app to the front — the
/// point of asking a watch to play something is not having to look at it.
/// Why an intent could not do what it was asked.
///
/// Siri reads the `failureReason` back, so these say what is missing rather
/// than that something went wrong: an intent that returns `.result()` after
/// doing nothing leaves the listener staring at a silent watch that just
/// told them it had started playing.
enum WatchPlaybackIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case stationUnavailable
    case nothingLoaded

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .stationUnavailable:
            "The live station isn't reachable right now."
        case .nothingLoaded:
            "There's nothing loaded to play on this watch."
        }
    }
}

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
        // `playLiveStream` schedules its own retry when the station is still
        // unknown, which would report success now and start audio later or
        // never. Better to say so.
        guard radio.nowPlaying != nil else {
            throw WatchPlaybackIntentError.stationUnavailable
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
        // `togglePlayPause` returns false only when there is no player, no
        // queued song and no download in flight — nothing a "resumed" reply
        // could be about.
        guard AudioManager.shared.togglePlayPause() else {
            throw WatchPlaybackIntentError.nothingLoaded
        }
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
