import SwiftUI
import WidgetKit
struct RadioEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String?

    static let placeholder = RadioEntry(
        date: .now,
        title: "Twinskaraoke Radio",
        artist: String(localized: "Live")
    )
}

struct RadioProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in _: Context) -> RadioEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RadioEntry) -> Void) {
        guard !context.isPreview else {
            completion(.placeholder)
            return
        }
        Task { completion(await Self.fetchEntry()) }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RadioEntry>) -> Void) {
        Task {
            let entry = await Self.fetchEntry()
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(Self.refreshInterval))
                )
            )
        }
    }
    private static func fetchEntry() async -> RadioEntry {
        var request = URLRequest(url: RadioStation.metadataURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let metadata = try? JSONDecoder().decode(RadioNowPlaying.self, from: data)
        else {
            return .placeholder
        }
        guard let song = metadata.nowPlaying?.song else {
            return RadioEntry(date: .now, title: metadata.station.name, artist: nil)
        }
        return RadioEntry(
            date: .now,
            title: song.title ?? song.text ?? metadata.station.name,
            artist: song.artist
        )
    }
}

struct RadioComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RadioEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
            }

        case .accessoryCorner:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .widgetLabel(inlineText)

        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Live Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                if let artist = entry.artist {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inlineText: String {
        guard let artist = entry.artist, !artist.isEmpty else { return entry.title }
        return "\(entry.title) — \(artist)"
    }
}

struct RadioComplication: Widget {
    static let kind = "TwinskaraokeRadioComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RadioProvider()) { entry in
            RadioComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Live Radio")
        .description("Shows what is playing on Twinskaraoke Radio.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
        ])
    }
}
