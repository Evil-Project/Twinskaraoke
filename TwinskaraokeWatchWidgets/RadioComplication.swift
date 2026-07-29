import SwiftUI
import WidgetKit

/// What the station is playing, on the watch face and in the Smart Stack.
///
/// Deliberately reads the public station metadata endpoint directly rather than
/// anything the app has stored. That keeps the complication working without an
/// App Group to share a container, without the Keychain, and without a signed-in
/// session — none of which a watch face is a good place to depend on.
struct RadioEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String?

    static let placeholder = RadioEntry(
        date: .now,
        title: "Twinskaraoke Radio",
        artist: "Live"
    )
}

struct RadioProvider: TimelineProvider {
    /// Watch complications get a small refresh budget, so this asks for less
    /// than the app's 15-second polling: a face is a glance, not a monitor.
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

    /// Falls back to the station name rather than an error state: a face that
    /// says "Twinskaraoke Radio" is more use than one showing a failure.
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
            // A single line the system styles itself; no artwork, no colour.
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
