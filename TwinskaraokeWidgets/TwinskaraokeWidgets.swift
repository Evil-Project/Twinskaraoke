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

struct LibraryEntry: TimelineEntry {
    var date = Date()
    var playlists: [PlaylistEntity]
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
    func placeholder(in context: Context) -> LibraryEntry { LibraryEntry(playlists: [PlaylistEntity(WidgetPlaylist(id: "preview", name: "Recently Played"))]) }
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
        return LibraryEntry(playlists: values.map(PlaylistEntity.init))
    }
}
struct WidgetArtwork: View {
    let filename: String?
    var symbol = "music.note.list"
    var cornerRadius: CGFloat = 12
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple, .indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url = WidgetArtworkStore().url(for: filename), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
            } else {
                Image(systemName: symbol).font(.title).foregroundStyle(.white).widgetAccentable()
            }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius)).accessibilityHidden(true)
    }
}
struct PlaylistWidgetArtwork: View {
    let playlist: PlaylistEntity
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            if playlist.id == "__favorites__" {
                ZStack {
                    Color(red: 0.94, green: 0.96, blue: 0.96)
                    Image(systemName: "star.fill")
                        .font(.system(size: side * 0.46, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.12, blue: 0.22))
                }.frame(width: side, height: side)
            } else if let filenames = playlist.artworkFilenames, filenames.count > 1 {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { column in
                                WidgetArtwork(filename: filenames[(row * 2 + column) % filenames.count], cornerRadius: 0)
                                    .frame(width: side / 2, height: side / 2)
                            }
                        }
                    }
                }.frame(width: side, height: side)
            } else {
                WidgetArtwork(filename: playlist.artworkFilenames?.first ?? playlist.artworkFilename)
                    .frame(width: side, height: side)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
struct LibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibraryEntry
    private var limit: Int { family == .systemSmall ? 1 : 4 }
    private var columns: Int { family == .systemSmall ? 1 : 4 }
    var body: some View {
        if entry.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "music.note.list").font(.largeTitle).widgetAccentable()
                Text("Your Music").font(.headline)
                Text("Open Twinskaraoke to choose a playlist.").font(.caption).foregroundStyle(.secondary)
            }.widgetURL(AppRoute.library.url)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 10) {
                ForEach(Array(entry.playlists.prefix(limit))) { playlist in
                    VStack(alignment: .leading, spacing: 4) {
                        Link(destination: playlist.route.url) { tile(playlist) }
                        Button(intent: IOSPlayPlaylistIntent(playlist: playlist)) {
                            Label("Play", systemImage: "play.fill").font(.caption2)
                        }.buttonStyle(.plain).accessibilityLabel("Play \(playlist.name)")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .privacySensitive()
            .widgetURL(entry.playlists[0].route.url)
        }
    }
    private func tile(_ playlist: PlaylistEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PlaylistWidgetArtwork(playlist: playlist)
                .frame(width: family == .systemSmall ? 76 : 64, height: family == .systemSmall ? 76 : 64)
            Text(playlist.name).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(height: 34, alignment: .topLeading).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
struct RecentlyPlayedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.recent, intent: RecentConfiguration.self, provider: RecentProvider()) {
            LibraryWidgetView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("Recently Played").description("Your recent, pinned, or favorite playlists.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct PlaybackEntry: TimelineEntry {
    var date = Date()
    var snapshot: PlaybackWidgetSnapshot
}
struct PlaybackProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaybackEntry { PlaybackEntry(snapshot: PlaybackWidgetSnapshot(song: WidgetSong(id: "preview", title: "Your Music", artist: "Twinskaraoke"))) }
    func getSnapshot(in context: Context, completion: @escaping (PlaybackEntry) -> Void) { completion(PlaybackEntry(snapshot: WidgetSnapshotStore().readPlayback())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaybackEntry>) -> Void) {
        completion(Timeline(entries: [PlaybackEntry(snapshot: WidgetSnapshotStore().readPlayback())], policy: .after(Date().addingTimeInterval(900))))
    }
}
struct PlaybackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PlaybackWidgetSnapshot

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        WidgetArtwork(filename: snapshot.song?.artworkFilename).frame(width: 58, height: 58)
                        Spacer(minLength: 6)
                        playButton
                    }
                    Spacer(minLength: 0)
                    metadata
                }
            default:
                VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                    HStack(spacing: 12) {
                        WidgetArtwork(filename: snapshot.song?.artworkFilename)
                            .frame(width: family == .systemLarge ? 64 : 48, height: family == .systemLarge ? 64 : 48)
                        metadata
                        Spacer(minLength: 0)
                    }
                    progressBar
                    transport
                    if family == .systemLarge {
                        Divider().opacity(0.5)
                        queuePreview
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive().widgetURL(AppRoute.nowPlaying.url)
    }

    private var playButton: some View {
        Button(intent: IOSTogglePlaybackIntent()) {
            Image(systemName: snapshot.isPlaying || snapshot.isBuffering == true ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.primary.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain).disabled(snapshot.song == nil)
        .accessibilityLabel(snapshot.isPlaying || snapshot.isBuffering == true ? "Pause" : "Play")
    }

    private var transport: some View {
        HStack(spacing: 0) {
            if family == .systemLarge || family == .systemMedium {
                Button(intent: IOSToggleShuffleIntent()) {
                    Image(systemName: "shuffle")
                        .frame(width: 40, height: 40)
                        .background(snapshot.isShuffled ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(snapshot.isShuffled ? Color.accentColor : Color.secondary)
                .accessibilityLabel("Toggle shuffle").accessibilityValue(snapshot.isShuffled ? "On" : "Off")
                .disabled(snapshot.song == nil || snapshot.isRadio)
            }
            Spacer(minLength: 4)
            Button(intent: IOSPreviousTrackIntent()) {
                Image(systemName: "backward.fill").frame(width: 44, height: 40)
            }.disabled(!snapshot.hasPrevious).accessibilityLabel("Previous Track")
            Spacer(minLength: 4)
            playButton
            Spacer(minLength: 4)
            Button(intent: IOSNextTrackIntent()) {
                Image(systemName: "forward.fill").frame(width: 44, height: 40)
            }.disabled(!snapshot.hasNext).accessibilityLabel("Next Track")
            Spacer(minLength: 4)
            if family == .systemLarge || family == .systemMedium {
                Button(intent: IOSToggleRepeatIntent()) {
                    Image(systemName: snapshot.repeatMode == "one" ? "repeat.1" : "repeat")
                        .frame(width: 40, height: 40)
                        .background(snapshot.repeatMode != "off" ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(snapshot.repeatMode == "off" ? Color.secondary : Color.accentColor)
                .accessibilityLabel("Toggle repeat").accessibilityValue(repeatDescription)
                .disabled(snapshot.song == nil || snapshot.isRadio)
            }
        }.buttonStyle(.plain).font(.system(size: 18, weight: .semibold)).widgetAccentable()
    }

    private var repeatDescription: String {
        switch snapshot.repeatMode {
        case "one": String(localized: "Repeat Once")
        case "all": String(localized: "Repeat")
        default: String(localized: "Don't Repeat")
        }
    }

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Up Next").font(.caption.weight(.semibold))
                Spacer()
                Text(snapshot.playbackMode).font(.caption2).foregroundStyle(.secondary)
            }
            if snapshot.queue.isEmpty {
                Text(snapshot.isRadio ? "Live Radio" : "No upcoming songs")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ForEach(Array(snapshot.queue.prefix(3).enumerated()), id: \.offset) { _, song in
                    HStack(spacing: 8) {
                        WidgetArtwork(filename: song.artworkFilename).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title).font(.caption.weight(.medium)).lineLimit(1)
                            Text(song.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var progressBar: some View {
        if snapshot.isRadio {
            HStack(spacing: 8) {
                Capsule().fill(.secondary.opacity(0.2)).frame(height: 3)
                Text("Live").font(.caption2.weight(.medium))
            }
        } else {
            Group {
                if let interval = snapshot.playbackInterval {
                    // WidgetKit advances the timer without per-second timeline reloads.
                    ProgressView(timerInterval: interval, countsDown: false).labelsHidden()
                } else {
                    ProgressView(value: snapshot.elapsed(at: snapshot.updatedAt), total: max(1, snapshot.durationSeconds ?? Double(snapshot.song?.duration ?? 0)))
                }
            }.tint(.accentColor).accessibilityLabel("Playback progress")
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.song?.title ?? String(localized: "Nothing Playing"))
                .font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Text(snapshot.song?.artist ?? "Twinskaraoke")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            if snapshot.isBuffering == true { Text("Loading…").font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.nowPlaying, provider: PlaybackProvider()) {
            PlaybackWidgetView(snapshot: $0.snapshot).containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("Now Playing").description("Your current song, playback controls, and queue.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RadioWidgetEntry: TimelineEntry {
    var date = Date()
    var title = "Twinskaraoke Radio"
    var artist = String(localized: "Live Radio")
    var artworkFilename: String?
}
struct RadioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadioWidgetEntry { RadioWidgetEntry() }
    func getSnapshot(in context: Context, completion: @escaping (RadioWidgetEntry) -> Void) { completion(RadioWidgetEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RadioWidgetEntry>) -> Void) {
        Task {
            let snapshot = await WidgetRadioRepository.fetch()
            let entry = RadioWidgetEntry(title: snapshot.title, artist: snapshot.artist, artworkFilename: snapshot.artworkFilename)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(WidgetRadioRepository.refreshInterval))))
        }
    }
}
struct LiveRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.radio, provider: RadioWidgetProvider()) {
            RadioWidgetView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("Live Radio").description("See what is on Twinskaraoke Radio and listen live.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct RadioWidgetView: View {
    let entry: RadioWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WidgetArtwork(filename: entry.artworkFilename, symbol: "dot.radiowaves.left.and.right")
                    .frame(width: 34, height: 34)
                Label("Live Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption).widgetAccentable()
            }
            Text(entry.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Text(entry.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Button(intent: IOSPlayRadioIntent()) {
                Label("Play Live", systemImage: "play.fill")
            }.font(.caption).buttonStyle(.plain)
        }.widgetURL(AppRoute.radio.url)
    }
}
