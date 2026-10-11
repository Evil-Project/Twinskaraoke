#if os(iOS)
import SwiftUI
import WidgetKit
import AppIntents

struct LibraryEntry: TimelineEntry {
    var date = Date()
    var playlists: [PlaylistEntity]
    var theme: SharedThemeDefinition = .builtIn(.dark)
}

struct WidgetArtwork: View {
    @Environment(\.widgetVisualTheme) private var visual
    let filename: String?
    var symbol = "music.note.list"
    var cornerRadius: CGFloat? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: [visual.accent, visual.paletteAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url = WidgetArtworkStore().url(for: filename), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
            } else {
                Image(systemName: symbol).font(.title).foregroundStyle(visual.text).widgetAccentable()
            }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? visual.variant.artworkRadius)).accessibilityHidden(true)
    }
}

struct PlaylistWidgetArtwork: View {
    @Environment(\.widgetVisualTheme) private var visual
    let playlist: PlaylistEntity
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            if playlist.id == "__favorites__" {
                ZStack {
                    visual.surface
                    Image(systemName: "star.fill")
                        .font(.system(size: side * 0.46, weight: .semibold))
                        .foregroundStyle(visual.accent)
                }.frame(width: side, height: side)
            } else if let filenames = playlist.artworkFilenames, filenames.count >= 4 {
                // A full grid only, matching the app: two or three covers
                // fall through to the single cover below instead of repeating.
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
        .clipShape(RoundedRectangle(cornerRadius: visual.variant.artworkRadius))
        .accessibilityHidden(true)
    }
}

struct LibraryWidgetView: View {
    @Environment(\.widgetVisualTheme) private var visual
    @Environment(\.widgetFamily) private var systemFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    let entry: LibraryEntry
    init(entry: LibraryEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry; self.familyOverride = familyOverride
    }
    private var limit: Int { family == .systemSmall ? 1 : 4 }
    private var columns: Int { family == .systemSmall ? 1 : 4 }
    var body: some View {
        if entry.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "music.note.list").font(.largeTitle).widgetAccentable()
                Text("Your Music").font(.headline)
                Text("Open Twinskaraoke to choose a playlist.").font(.caption).foregroundStyle(visual.secondaryText)
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
                .frame(height: 34, alignment: .topLeading).foregroundStyle(visual.text)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct PlaybackEntry: TimelineEntry {
    var date = Date()
    var snapshot: PlaybackWidgetSnapshot
    var theme: SharedThemeDefinition = .builtIn(.dark)
}

struct PlaybackWidgetView: View {
    @Environment(\.widgetVisualTheme) private var visual
    @Environment(\.widgetFamily) private var systemFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    let snapshot: PlaybackWidgetSnapshot
    init(snapshot: PlaybackWidgetSnapshot, familyOverride: WidgetFamily? = nil) {
        self.snapshot = snapshot; self.familyOverride = familyOverride
    }

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
                .background(visual.controlFill, in: Circle())
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
                        .background(snapshot.isShuffled ? visual.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: visual.variant.artworkRadius))
                }
                .foregroundStyle(snapshot.isShuffled ? visual.accent : visual.secondaryText)
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
                        .background(snapshot.repeatMode != "off" ? visual.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: visual.variant.artworkRadius))
                }
                .foregroundStyle(snapshot.repeatMode == "off" ? visual.secondaryText : visual.accent)
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
                Text(snapshot.playbackMode).font(.caption2).foregroundStyle(visual.secondaryText)
            }
            if snapshot.queue.isEmpty {
                Text(snapshot.isRadio ? "Live Radio" : "No upcoming songs")
                    .font(.caption).foregroundStyle(visual.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ForEach(Array(snapshot.queue.prefix(3).enumerated()), id: \.offset) { _, song in
                    HStack(spacing: 8) {
                        WidgetArtwork(filename: song.artworkFilename).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title).font(.caption.weight(.medium)).lineLimit(1)
                            Text(song.artist).font(.caption2).foregroundStyle(visual.secondaryText).lineLimit(1)
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
                Capsule().fill(visual.divider).frame(height: 3)
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
            }.tint(visual.accent).accessibilityLabel("Playback progress")
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.song?.title ?? String(localized: "Nothing Playing"))
                .font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Text(snapshot.song?.artist ?? "Twinskaraoke")
                .font(.caption).foregroundStyle(visual.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
            if snapshot.isBuffering == true { Text("Loading…").font(.caption2).foregroundStyle(visual.secondaryText) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RadioWidgetEntry: TimelineEntry {
    var date = Date()
    var snapshot = WidgetRadioSnapshot()
    var theme: SharedThemeDefinition = .builtIn(.dark)
}

struct RadioWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    @Environment(\.widgetVisualTheme) private var visual
    let entry: RadioWidgetEntry
    init(entry: RadioWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry; self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                GeometryReader { geometry in
                    let widths = RadioWidgetColumns(availableWidth: geometry.size.width, gap: visual.variant.columnGap)
                    HStack(spacing: visual.variant.columnGap) {
                        information.frame(width: widths.information, height: geometry.size.height, alignment: .leading)
                        listeners.frame(width: widths.listeners, height: geometry.size.height, alignment: .center)
                    }
                }
            } else {
                information
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(AppRoute.radio.url)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WidgetArtwork(filename: entry.snapshot.artworkFilename, symbol: "dot.radiowaves.left.and.right")
                    .frame(width: 34, height: 34)
                Label("Live Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption).lineLimit(2).widgetAccentable()
            }
            Text(entry.snapshot.title).font(.headline).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.snapshot.artist.isEmpty {
                Text(entry.snapshot.artist).font(.caption).foregroundStyle(visual.secondaryText).lineLimit(1)
            }
            Button(intent: IOSPlayRadioIntent()) {
                Label("Play Live", systemImage: "play.fill")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .foregroundStyle(visual.accent)
                    .background(visual.controlFill, in: Capsule())
            }.buttonStyle(.plain).widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listeners: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.2.fill").font(.caption).foregroundStyle(visual.accent).widgetAccentable()
            ViewThatFits(in: .horizontal) {
                listenerCount.font(.title2.bold())
                listenerCount.font(.headline)
                if let count = entry.snapshot.listeners {
                    Text(count, format: .number.notation(.compactName)).font(.headline.bold())
                }
            }
            Text("Listeners").font(.caption2).foregroundStyle(visual.secondaryText).lineLimit(2)
            if entry.snapshot.listeners == nil {
                Text("Unavailable").font(.caption2).foregroundStyle(visual.secondaryText).lineLimit(2)
            }
            if entry.snapshot.listeners != nil, let fetchedAt = entry.snapshot.fetchedAt {
                // Show the successful-fetch time, never a timestamp from a failed retry.
                Text("Last updated").font(.caption2).foregroundStyle(visual.secondaryText).lineLimit(2)
                Text(fetchedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2).foregroundStyle(visual.secondaryText).lineLimit(2)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .padding(.leading, 6)
        .overlay(alignment: .leading) {
            Rectangle().fill(visual.divider).frame(width: 0.5).padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var listenerCount: some View {
        if let count = entry.snapshot.listeners { Text(count, format: .number) }
        else { Text("—") }
    }
}

/// Widths are relative to WidgetKit's usable content bounds, after its margins.
nonisolated struct RadioWidgetColumns {
    let information: Double
    let listeners: Double
    init(availableWidth: Double, gap: Double) {
        let usable = max(0, availableWidth - gap)
        information = usable * 2 / 3
        listeners = usable / 3
    }
}

#endif
