import SwiftUI
import WidgetKit
import AppIntents

@main
struct TwinskaraokeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentlyPlayedWidget()
        NowPlayingWidget()
        LiveRadioWidget()
        PlaylistControl()
        NextTrackControl()
        PreviousTrackControl()
        RadioControl()
        FavoritesControl()
        DownloadsControl()
        RepeatControl()
        ShuffleControl()
        FavoriteCurrentSongControl()
        SleepTimerControl()
    }
}

nonisolated enum LibrarySource: String, AppEnum {
    case recent, pinned, favorites
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .recent: "Recently Played", .pinned: "Pinned Playlists", .favorites: "Favorites"
    ]
}
struct RecentConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Collection"
    @Parameter(title: "Collection", default: .recent) var source: LibrarySource
}
struct RecentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry { LibraryEntry(playlists: [PlaylistEntity(WidgetPlaylist(id: "preview", name: "Recently Played"))], theme: WidgetSnapshotStore().readTheme().definition) }
    func snapshot(for configuration: RecentConfiguration, in context: Context) async -> LibraryEntry { entry(configuration) }
    func timeline(for configuration: RecentConfiguration, in context: Context) async -> Timeline<LibraryEntry> { Timeline(entries: [entry(configuration)], policy: .never) }
    private func entry(_ configuration: RecentConfiguration) -> LibraryEntry {
        let library = WidgetSnapshotStore().readLibrary()
        let values: [WidgetPlaylist]
        switch configuration.source {
        case .recent: values = library.recent
        case .pinned: values = library.pinned
        case .favorites: values = library.suggestions.filter { $0.id == "__favorites__" }
        }
        return LibraryEntry(playlists: values.map(PlaylistEntity.init), theme: WidgetSnapshotStore().readTheme().definition)
    }
}
struct RecentlyPlayedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.recent, intent: RecentConfiguration.self, provider: RecentProvider()) { entry in
            WidgetThemedView(theme: entry.theme) { LibraryWidgetView(entry: entry) }
        }.configurationDisplayName("Recently Played").description("Your recent, pinned, or favorite playlists.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct PlaybackProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaybackEntry { PlaybackEntry(snapshot: PlaybackWidgetSnapshot(song: WidgetSong(id: "preview", title: "Your Music", artist: "Twinskaraoke")), theme: WidgetSnapshotStore().readTheme().definition) }
    func getSnapshot(in context: Context, completion: @escaping (PlaybackEntry) -> Void) { completion(PlaybackEntry(snapshot: WidgetSnapshotStore().readPlayback(), theme: WidgetSnapshotStore().readTheme().definition)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaybackEntry>) -> Void) {
        completion(Timeline(entries: [PlaybackEntry(snapshot: WidgetSnapshotStore().readPlayback(), theme: WidgetSnapshotStore().readTheme().definition)], policy: .after(Date().addingTimeInterval(900))))
    }
}
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.nowPlaying, provider: PlaybackProvider()) { entry in
            WidgetThemedView(theme: entry.theme) { PlaybackWidgetView(snapshot: entry.snapshot) }
        }.configurationDisplayName("Now Playing").description("Your current song, playback controls, and queue.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RadioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadioWidgetEntry { RadioWidgetEntry(theme: WidgetSnapshotStore().readTheme().definition) }
    func getSnapshot(in context: Context, completion: @escaping (RadioWidgetEntry) -> Void) { completion(RadioWidgetEntry(snapshot: WidgetSnapshotStore().readRadio(), theme: WidgetSnapshotStore().readTheme().definition)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RadioWidgetEntry>) -> Void) {
        Task {
            let snapshot = await WidgetRadioRepository.fetch()
            let entry = RadioWidgetEntry(snapshot: snapshot, theme: WidgetSnapshotStore().readTheme().definition)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(WidgetRadioRepository.refreshInterval))))
        }
    }
}
struct LiveRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.radio, provider: RadioWidgetProvider()) { entry in
            WidgetThemedView(theme: entry.theme) { RadioWidgetView(entry: entry) }
        }.configurationDisplayName("Live Radio").description("See what is on Twinskaraoke Radio and listen live.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
