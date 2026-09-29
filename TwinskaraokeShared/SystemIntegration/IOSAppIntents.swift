#if os(iOS)
import AppIntents
import Foundation

nonisolated enum SystemIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingLoaded, noNext, noPrevious, stationUnavailable, signIn, emptyCollection, choosePlaylist, favoriteFailed, liveTimer, appRequired, playbackUnavailable
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingLoaded: "There is no song loaded. Open Twinskaraoke and choose a song first."
        case .noNext: "There is no next song in this queue."
        case .noPrevious: "There is no previous song in this queue."
        case .stationUnavailable: "The live station is unavailable. Try again later."
        case .signIn: "Sign in to Twinskaraoke to use your favorites and personal playlists."
        case .emptyCollection: "There are no playable songs in this collection."
        case .choosePlaylist: "Choose a playlist in the Control Center control settings."
        case .favoriteFailed: "The song could not be added to favorites. Please try again."
        case .liveTimer: "A live stream has no song ending. Choose a timed sleep timer."
        case .playbackUnavailable: "Playback has not started. Check your connection and try again in Twinskaraoke."
        case .appRequired: "Open Twinskaraoke to perform this action."
        }
    }
}
#if WIDGET_EXTENSION
/// Widget audio intents are dispatched to the containing app by App Intents.
/// Fail explicitly if the system invokes an extension-only fallback.
private func requireApplicationProcess() throws {
    throw SystemIntentError.appRequired
}
#endif
nonisolated enum PlaybackAction: String, AppEnum {
    case toggle, next, previous, radio, favorites, downloads, playlist
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback Action"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toggle: "Play or Pause", .next: "Next Track", .previous: "Previous Track",
        .radio: "Live Radio", .favorites: "Favorites", .downloads: "Downloaded Songs",
        .playlist: "Playlist"
    ]
}
nonisolated enum SleepTimerDuration: String, AppEnum {
    case fifteen, thirty, fortyFive, hour, endOfSong
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Timer Duration"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fifteen: "15 minutes", .thirty: "30 minutes", .fortyFive: "45 minutes",
        .hour: "1 hour", .endOfSong: "End of song"
    ]
    var minutes: Int {
        switch self { case .fifteen: 15; case .thirty: 30; case .fortyFive: 45; case .hour: 60; case .endOfSong: 0 }
    }
}

struct IOSPlayRadioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Twinskaraoke Radio"
    static let description = IntentDescription("Play Twinskaraoke Radio in Twinskaraoke.")
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.radio, shuffle: false)
        #endif
        return .result()
    }
}

struct IOSTogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Play or Pause in Twinskaraoke.")
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.toggle, shuffle: false)
        #endif
        return .result()
    }
}

struct IOSNextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Next Track in Twinskaraoke.")
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.next, shuffle: false)
        #endif
        return .result()
    }
}

struct IOSPreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Previous Track in Twinskaraoke.")
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.previous, shuffle: false)
        #endif
        return .result()
    }
}

struct IOSPlayFavoritesIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Favorites"
    @Parameter(title: "Shuffle", default: false) var shuffle: Bool
    @Parameter(title: "Repeat", default: .off) var repeatMode: IntentRepeatMode
    @Parameter(title: "Sleep Timer") var sleepTimer: SleepTimerDuration?
    static var parameterSummary: some ParameterSummary { Summary("Play Favorites") { \.$shuffle; \.$repeatMode; \.$sleepTimer } }
    init() {}
    init(shuffle: Bool) { self.shuffle = shuffle }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.favorites, shuffle: shuffle, repeatMode: repeatMode)
        if let sleepTimer { try IntentPlaybackController.startSleepTimer(sleepTimer) }
        #endif
        return .result()
    }
}
struct IOSPlayDownloadsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Downloaded Songs"
    @Parameter(title: "Shuffle", default: false) var shuffle: Bool
    @Parameter(title: "Repeat", default: .off) var repeatMode: IntentRepeatMode
    @Parameter(title: "Sleep Timer") var sleepTimer: SleepTimerDuration?
    static var parameterSummary: some ParameterSummary { Summary("Play Downloaded Songs") { \.$shuffle; \.$repeatMode; \.$sleepTimer } }
    init() {}
    init(shuffle: Bool) { self.shuffle = shuffle }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.downloads, shuffle: shuffle, repeatMode: repeatMode)
        if let sleepTimer { try IntentPlaybackController.startSleepTimer(sleepTimer) }
        #endif
        return .result()
    }
}

struct IOSPlayPlaylistIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Playlist"
    @Parameter(title: "Playlist") var playlist: PlaylistEntity
    @Parameter(title: "Shuffle", default: false) var shuffle: Bool
    @Parameter(title: "Repeat", default: .off) var repeatMode: IntentRepeatMode
    @Parameter(title: "Sleep Timer") var sleepTimer: SleepTimerDuration?
    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$playlist)") { \.$shuffle; \.$repeatMode; \.$sleepTimer } }
    init() {}
    init(shuffle: Bool) { self.shuffle = shuffle }
    init(playlist: PlaylistEntity, shuffle: Bool = false) { self.playlist = playlist; self.shuffle = shuffle }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.perform(.playlist, playlistID: playlist.id, shuffle: shuffle, repeatMode: repeatMode)
        if let sleepTimer { try IntentPlaybackController.startSleepTimer(sleepTimer) }
        #endif
        return .result()
    }
}
struct IOSControlPlayPlaylistIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Playlist Control"
    static let isDiscoverable = false
    @Parameter(title: "Playlist") var playlist: PlaylistEntity?
    init() {}
    init(playlist: PlaylistEntity?) { self.playlist = playlist }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        guard let playlist else { throw SystemIntentError.choosePlaylist }
        try await IntentPlaybackController.perform(.playlist, playlistID: playlist.id)
        #endif
        return .result()
    }
}
#if !WIDGET_EXTENSION
struct IOSFavoriteCurrentSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Current Song to Favorites"
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.favoriteCurrentSong()
        #endif
        return .result()
    }
}
struct IOSStartSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Sleep Timer"
    @Parameter(title: "Duration", default: .thirty) var duration: SleepTimerDuration
    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$duration) sleep timer") }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try IntentPlaybackController.startSleepTimer(duration)
        #endif
        return .result()
    }
}
struct IOSOpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Search"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppRouter.shared.open(.search)
        #endif
        return .result()
    }
}
#endif
struct IOSOpenLyricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Lyrics"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        guard AudioPlayerManager.shared.currentSong != nil else { throw SystemIntentError.nothingLoaded }
        AppRouter.shared.open(.lyrics)
        #endif
        return .result()
    }
}
/// Control Center actions that require the app process use an app-opening
/// intent. The corresponding Shortcuts actions keep their background behavior.
struct IOSControlFavoriteCurrentSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Favorite This Song"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try await IntentPlaybackController.favoriteCurrentSong()
        #endif
        return .result()
    }
}
struct IOSControlSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Sleep Timer"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "Duration", default: .thirty) var duration: SleepTimerDuration
    init() {}
    init(duration: SleepTimerDuration) { self.duration = duration }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        try IntentPlaybackController.startSleepTimer(duration)
        #endif
        return .result()
    }
}
#if !WIDGET_EXTENSION
struct IOSShowCurrentSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Current Song"
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        #if !WIDGET_EXTENSION
        WidgetSnapshotPublisher.shared.start()
        WidgetSnapshotPublisher.shared.publish()
        #endif
        guard let song = WidgetSnapshotStore().readPlayback().song else { throw SystemIntentError.nothingLoaded }
        let value = song.artist.isEmpty ? song.title : "\(song.title) — \(song.artist)"
        return .result(value: value, dialog: "\(value)")
    }
}

#endif
nonisolated enum IntentRepeatMode: String, AppEnum {
    case off, all, one
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Repeat"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.off: "Don't Repeat", .all: "Repeat", .one: "Repeat Once"]
}
nonisolated enum PlaybackSetting { case toggleRepeat, toggleShuffle }
struct IOSToggleRepeatIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Toggle Repeat"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        return .result(dialog: "Open Twinskaraoke to perform this action.")
        #else
        let result = try IntentPlaybackController.changeSetting(.toggleRepeat)
        return .result(dialog: "\(result)")
        #endif
    }
}
struct IOSToggleShuffleIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Toggle Shuffle"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        return .result(dialog: "Open Twinskaraoke to perform this action.")
        #else
        let result = try IntentPlaybackController.changeSetting(.toggleShuffle)
        return .result(dialog: "\(result)")
        #endif
    }
}
nonisolated enum TransportAction: String, AppEnum {
    case toggle, next, previous
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback Control"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.toggle: "Play or pause", .next: "Next track", .previous: "Previous track"]
}
struct IOSTransportIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Control Playback"
    @Parameter(title: "Control", default: .toggle) var action: TransportAction
    static var parameterSummary: some ParameterSummary { Summary("\(\.$action)") }
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireApplicationProcess()
        #else
        let action: PlaybackAction = switch action { case .toggle: .toggle; case .next: .next; case .previous: .previous }
        try await IntentPlaybackController.perform(action)
        #endif
        return .result()
    }
}
#endif
