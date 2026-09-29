import AppIntents

struct IOSAppShortcuts: AppShortcutsProvider {
    // Keep the automatic page to ten actions. Playlist names are resolved in
    // the Play Playlist picker rather than donated as hundreds of tiles.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: IOSPlayPlaylistIntent(), phrases: [
            "Play a playlist in \(.applicationName)"
        ], shortTitle: "Play Playlist", systemImageName: "music.note.list")
        AppShortcut(intent: IOSPlayFavoritesIntent(), phrases: [
            "Play my favorites in \(.applicationName)",
            "Play my favorites playlist in \(.applicationName)"
        ], shortTitle: "Play Favorites", systemImageName: "star.fill")
        AppShortcut(intent: IOSPlayDownloadsIntent(), phrases: [
            "Play downloaded songs in \(.applicationName)"
        ], shortTitle: "Play Downloads", systemImageName: "arrow.down.circle")
        AppShortcut(intent: IOSPlayRadioIntent(), phrases: ["Play radio in \(.applicationName)"], shortTitle: "Play Radio", systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: IOSNextTrackIntent(), phrases: ["Next track in \(.applicationName)"], shortTitle: "Next Track", systemImageName: "forward.fill")
        AppShortcut(intent: IOSPreviousTrackIntent(), phrases: ["Previous track in \(.applicationName)"], shortTitle: "Previous Track", systemImageName: "backward.fill")
        AppShortcut(intent: IOSToggleRepeatIntent(), phrases: ["Toggle repeat in \(.applicationName)", "Change repeat mode in \(.applicationName)", "Repeat in \(.applicationName)"], shortTitle: "Toggle Repeat", systemImageName: "repeat")
        AppShortcut(intent: IOSToggleShuffleIntent(), phrases: ["Toggle shuffle in \(.applicationName)", "Shuffle \(.applicationName)", "Shuffle playback in \(.applicationName)"], shortTitle: "Toggle Shuffle", systemImageName: "shuffle")
        AppShortcut(intent: IOSFavoriteCurrentSongIntent(), phrases: ["Favorite this song in \(.applicationName)", "Add this song to my favorites in \(.applicationName)"], shortTitle: "Favorite This Song", systemImageName: "star")
        AppShortcut(intent: IOSStartSleepTimerIntent(), phrases: ["Start a sleep timer in \(.applicationName)"], shortTitle: "Sleep Timer", systemImageName: "moon.zzz")
    }
}
