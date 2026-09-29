import SwiftUI
import WidgetKit
import AppIntents

struct PlaylistControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Play Playlist"
    @Parameter(title: "Playlist") var playlist: PlaylistEntity?
}
struct PlaylistControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TwinskaraokeControlPlaylist", intent: PlaylistControlConfiguration.self) { configuration in
            ControlWidgetButton(action: IOSControlPlayPlaylistIntent(playlist: configuration.playlist)) {
                Label("Play Playlist", systemImage: "music.note.list")
            }
        }.displayName("Play Playlist").description("Play your chosen playlist in Twinskaraoke.")
    }
}
struct NextTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlNextTrack") {
            ControlWidgetButton(action: IOSNextTrackIntent()) { Label("Next Track", systemImage: "forward.fill") }
        }.displayName("Next Track").description("Next Track in Twinskaraoke.")
    }
}
struct PreviousTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlPreviousTrack") {
            ControlWidgetButton(action: IOSPreviousTrackIntent()) { Label("Previous Track", systemImage: "backward.fill") }
        }.displayName("Previous Track").description("Previous Track in Twinskaraoke.")
    }
}
struct RadioControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlRadio") {
            ControlWidgetButton(action: IOSPlayRadioIntent()) { Label("Play Live Radio", systemImage: "dot.radiowaves.left.and.right") }
        }.displayName("Play Live Radio").description("Play Live Radio in Twinskaraoke.")
    }
}
struct FavoritesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlFavorites") {
            ControlWidgetButton(action: IOSPlayFavoritesIntent()) { Label("Play Favorites", systemImage: "star.fill") }
        }.displayName("Play Favorites").description("Play Favorites in Twinskaraoke.")
    }
}
struct DownloadsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlDownloads") {
            ControlWidgetButton(action: IOSPlayDownloadsIntent()) { Label("Play Downloads", systemImage: "arrow.down.circle") }
        }.displayName("Play Downloads").description("Play downloaded songs in Twinskaraoke.")
    }
}
struct RepeatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlRepeat") {
            ControlWidgetButton(action: IOSToggleRepeatIntent()) { Label("Toggle Repeat", systemImage: "repeat") }
        }.displayName("Toggle Repeat").description("Cycle the playlist repeat mode in Twinskaraoke.")
    }
}
struct ShuffleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlShuffle") {
            ControlWidgetButton(action: IOSToggleShuffleIntent()) { Label("Toggle Shuffle", systemImage: "shuffle") }
        }.displayName("Toggle Shuffle").description("Toggle shuffle in Twinskaraoke.")
    }
}
struct FavoriteCurrentSongControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TwinskaraokeControlFavoriteSong") {
            ControlWidgetButton(action: IOSControlFavoriteCurrentSongIntent()) {
                Label("Favorite This Song", systemImage: "star")
            }
        }.displayName("Favorite This Song").description("Add the current song to your favorites in Twinskaraoke.")
    }
}
struct SleepTimerControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Sleep Timer"
    @Parameter(title: "Duration", default: .thirty) var duration: SleepTimerDuration
}
struct SleepTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TwinskaraokeControlSleepTimer", intent: SleepTimerControlConfiguration.self) { configuration in
            ControlWidgetButton(action: IOSControlSleepTimerIntent(duration: configuration.duration)) {
                Label("Sleep Timer", systemImage: "moon.zzz")
            }
        }.displayName("Sleep Timer").description("Start a sleep timer in Twinskaraoke.")
    }
}
