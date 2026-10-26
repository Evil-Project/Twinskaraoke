import AppIntents
import Foundation
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
        if radio.nowPlaying == nil {
            await radio.refresh()
        }
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
        guard AudioManager.shared.togglePlayPause() else {
            throw WatchPlaybackIntentError.nothingLoaded
        }
        return .result()
    }
}
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
