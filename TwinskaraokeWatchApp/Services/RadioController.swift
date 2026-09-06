import Foundation
import Observation

/// Live station metadata for the watch.
///
/// Separate from the phone's `RadioController` for the same reason
/// `AudioManager` is: the two targets drive completely different players. The
/// wire format and the polling contract are shared through `RadioNowPlaying`.
@MainActor
@Observable
final class RadioController {
    static let shared = RadioController()

    private(set) var nowPlaying: RadioNowPlaying?
    private(set) var isRefreshing = false
    private(set) var refreshErrorMessage: String?

    /// Polling is driven by the radio screen being on-wrist, not by a timer
    /// that outlives it: a watch that keeps hitting the network with the
    /// display off is a battery complaint.
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var lastMetadataSignature: String?
    private var isScreenVisible = false
    private let pollInterval: Duration = .seconds(15)

    private init() {}

    func start() {
        isScreenVisible = true
        guard !AppRuntime.isUITestMode else {
            applyUITestFixture()
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, self.shouldKeepPolling else { break }
            }
            if !Task.isCancelled { self?.clearPollTask() }
        }
    }

    /// Leaves polling running while the station is still streaming — the Now
    /// Playing card outlives the radio screen — and lets the loop retire itself
    /// once playback ends.
    func stop() {
        isScreenVisible = false
        guard !AudioManager.shared.isRadioMode else { return }
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private var shouldKeepPolling: Bool {
        isScreenVisible || AudioManager.shared.isRadioMode
    }

    private func clearPollTask() {
        pollTask = nil
    }

    /// Tunes in, fetching metadata first if the station is not known yet.
    func playLiveStream() {
        guard let metadata = nowPlaying else {
            Task { [weak self] in
                await self?.refresh()
                guard self?.nowPlaying != nil else { return }
                self?.playLiveStream()
            }
            return
        }
        guard let streamURL = URL(string: metadata.station.listenUrl) else { return }
        let info = metadata.nowPlaying?.song
        let song = (info ?? fallbackSongInfo(for: metadata.station))
            .toSong(stationID: RadioStation.id)
        AudioManager.shared.playRadio(
            streamURL: streamURL,
            song: song,
            artworkURL: info?.art.flatMap { URL(string: $0) }
        )
    }

    func refresh() async {
        guard !AppRuntime.isUITestMode else {
            applyUITestFixture()
            return
        }
        // Coalesce: the view's pull-to-refresh and the poll loop can land
        // together, and two in-flight fetches would race to set `nowPlaying`.
        if let existing = refreshTask {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            await self?.performRefresh()
            if !Task.isCancelled { self?.refreshTask = nil }
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard !Task.isCancelled else { return }
        isRefreshing = true
        defer {
            if !Task.isCancelled { isRefreshing = false }
        }

        do {
            var request = URLRequest(url: RadioStation.metadataURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let metadata = try JSONDecoder().decode(RadioNowPlaying.self, from: data)
            guard !Task.isCancelled else { return }
            nowPlaying = metadata
            refreshErrorMessage = nil
            prefetchArtwork(from: metadata)
            applyMetadataToPlayer(metadata)
        } catch {
            guard !Task.isCancelled else { return }
            // A failed poll while already tuned in is a blip, not an outage:
            // the stream keeps playing, so say less about it.
            refreshErrorMessage = nowPlaying == nil
                ? "Radio is temporarily unavailable."
                : "Couldn't refresh what's playing."
        }
    }

    /// Pushes a track change into the Now Playing card while the stream itself
    /// keeps running, and only when something actually changed.
    private func applyMetadataToPlayer(_ metadata: RadioNowPlaying) {
        guard AudioManager.shared.isRadioMode,
              let info = metadata.nowPlaying?.song
        else { return }
        let signature = metadataSignature(for: info)
        guard signature != lastMetadataSignature else { return }
        lastMetadataSignature = signature
        AudioManager.shared.updateRadioMetadata(
            song: info.toSong(stationID: RadioStation.id),
            artworkURL: info.art.flatMap { URL(string: $0) }
        )
    }

    private func metadataSignature(for info: RadioNowPlaying.SongInfo) -> String {
        [
            info.resolvedSongID ?? info.id,
            info.title ?? info.text ?? "",
            info.artist ?? "",
            info.art ?? "",
        ].joined(separator: "|")
    }

    private func fallbackSongInfo(for station: RadioNowPlaying.Station) -> RadioNowPlaying.SongInfo {
        RadioNowPlaying.SongInfo(
            id: RadioStation.id,
            art: nil,
            text: station.name,
            artist: station.description,
            title: station.name,
            customFields: nil
        )
    }

    private func prefetchArtwork(from metadata: RadioNowPlaying) {
        let urls = [
            metadata.nowPlaying?.song.art,
            metadata.playingNext?.song.art,
        ].compactMap { $0.flatMap(URL.init(string:)) }
            + (metadata.songHistory ?? [])
            .prefix(4)
            .compactMap { $0.song.art.flatMap(URL.init(string:)) }
        WatchArtworkPrefetcher.shared.prefetch(urls: urls, reason: "radio", limit: 6)
    }

    private func applyUITestFixture() {
        nowPlaying = Self.uiTestNowPlaying
        refreshErrorMessage = nil
        isRefreshing = false
    }

    private static var uiTestNowPlaying: RadioNowPlaying {
        RadioNowPlaying(
            station: RadioNowPlaying.Station(
                name: "Twinskaraoke Radio",
                description: "Neuro 21 live from the karaoke room",
                listenUrl: "https://radio.twinskaraoke.com/listen/neuro_21/radio.mp3"
            ),
            listeners: RadioNowPlaying.Listeners(total: 42, unique: 24),
            nowPlaying: RadioNowPlaying.NowPlayingItem(
                song: RadioNowPlaying.SongInfo(
                    id: "ui-radio-song-1",
                    art: nil,
                    text: "Wake Me Up Before You Go-Go - Wham!",
                    artist: "Wham!",
                    title: "Wake Me Up Before You Go-Go",
                    customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-1")
                )
            ),
            playingNext: RadioNowPlaying.NowPlayingItem(
                song: RadioNowPlaying.SongInfo(
                    id: "ui-radio-song-2",
                    art: nil,
                    text: "Hero - Mili",
                    artist: "Mili",
                    title: "Hero",
                    customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-2")
                )
            ),
            songHistory: [
                RadioNowPlaying.HistoryItem(
                    song: RadioNowPlaying.SongInfo(
                        id: "ui-radio-song-3",
                        art: nil,
                        text: "Cure For Me - AURORA",
                        artist: "AURORA",
                        title: "Cure For Me",
                        customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-3")
                    )
                ),
            ]
        )
    }
}
