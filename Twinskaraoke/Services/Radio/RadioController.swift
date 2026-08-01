import Combine
import Foundation

@MainActor
final class RadioController: ObservableObject {
    typealias MetadataLoader = @Sendable () async throws -> RadioNowPlaying
    typealias PlaybackStarter = @MainActor (_ streamURL: URL, _ song: Song, _ artworkURL: URL?) -> Void

    static let shared = RadioController()
    static let metadataURL = URL(
        string: "https://radio.twinskaraoke.com/api/nowplaying_static/neuro_21.json"
    )!
    static let stationID = "neuro_21"
    @Published var nowPlaying: RadioNowPlaying?
    @Published var isRefreshing = false
    @Published var refreshErrorMessage: String?
    @Published var lastUpdated: Date?
    private var pollTimer: Timer?
    private var pollingGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var playbackRequestTask: Task<Void, Never>?
    private var playbackRequestGeneration = 0
    private var lastMetadataSignature: String?
    private let metadataLoader: MetadataLoader
    private let playbackStarter: PlaybackStarter

    init(
        metadataLoader: @escaping MetadataLoader = {
            let (data, response) = try await URLSession.shared.data(from: RadioController.metadataURL)
            guard let response = response as? HTTPURLResponse,
                (200 ..< 300).contains(response.statusCode)
            else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(RadioNowPlaying.self, from: data)
        },
        playbackStarter: @escaping PlaybackStarter = { streamURL, song, artworkURL in
            AudioPlayerManager.shared.playRadio(
                streamURL: streamURL,
                song: song,
                artworkURL: artworkURL
            )
        }
    ) {
        self.metadataLoader = metadataLoader
        self.playbackStarter = playbackStarter
    }

    func start() {
        pollingGeneration &+= 1
        let generation = pollingGeneration
        if AppRuntime.isUITestMode {
            pollTimer?.invalidate()
            pollTimer = nil
            refreshTask?.cancel()
            refreshTask = nil
            applyUITestFixture()
            return
        }

        // Register the initial refresh before returning so stop() can always
        // cancel it, even when start and stop happen in the same run-loop turn.
        beginRefresh()
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, pollingGeneration == generation, pollTimer != nil else { return }
                beginRefresh()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        pollingGeneration &+= 1
        pollTimer?.invalidate()
        pollTimer = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        cancelPendingPlaybackRequest()
    }

    func playLiveStream() {
        cancelPendingPlaybackRequest()
        guard let nowPlaying else {
            let generation = playbackRequestGeneration
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await refresh()
                guard generation == playbackRequestGeneration, !Task.isCancelled else { return }
                if let nowPlaying {
                    startLiveStream(from: nowPlaying)
                }
                guard generation == playbackRequestGeneration else { return }
                playbackRequestTask = nil
            }
            playbackRequestTask = task
            return
        }

        startLiveStream(from: nowPlaying)
    }

    func cancelPendingPlaybackRequest() {
        playbackRequestGeneration &+= 1
        playbackRequestTask?.cancel()
        playbackRequestTask = nil
    }

    private func startLiveStream(from metadata: RadioNowPlaying) {
        guard let streamURL = URL(string: metadata.station.listenUrl) else { return }
        let info = metadata.nowPlaying?.song
        let song =
            (info
                ?? RadioNowPlaying.SongInfo(
                    id: Self.stationID, art: nil, text: metadata.station.name,
                    artist: metadata.station.description, title: metadata.station.name,
                    customFields: nil
                )).toSong(stationID: Self.stationID)
        let artURL = info?.art.flatMap { URL(string: $0) }
        playbackStarter(streamURL, song, artURL)
    }

    func refresh() async {
        if AppRuntime.isUITestMode {
            applyUITestFixture()
            return
        }

        let task = beginRefresh()
        await task.value
    }

    @discardableResult
    private func beginRefresh() -> Task<Void, Never> {
        if let existing = refreshTask {
            return existing
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performRefresh(generation: generation)
            guard generation == refreshGeneration else { return }
            refreshTask = nil
        }
        refreshTask = task
        return task
    }

    private func performRefresh(generation: Int) async {
        guard generation == refreshGeneration else { return }
        isRefreshing = true
        defer {
            if generation == refreshGeneration {
                isRefreshing = false
            }
        }

        let maxRetries = 3

        for attempt in 0 ..< maxRetries {
            do {
                let np = try await metadataLoader()
                guard generation == refreshGeneration, !Task.isCancelled else { return }
                nowPlaying = np
                prefetchArtwork(from: np)
                refreshErrorMessage = nil
                lastUpdated = .now
                if AudioPlayerManager.shared.isRadioMode, let info = np.nowPlaying?.song {
                    let signature = metadataSignature(for: info)
                    if signature != lastMetadataSignature {
                        lastMetadataSignature = signature
                        let song = info.toSong(stationID: Self.stationID)
                        let art = info.art.flatMap { URL(string: $0) }
                        AudioPlayerManager.shared.updateRadioMetadata(song: song, artworkURL: art)
                    }
                }
                return
            } catch {
                guard !Task.isCancelled else { return }
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                }
            }
        }

        guard generation == refreshGeneration, !Task.isCancelled else { return }
        refreshErrorMessage =
            nowPlaying == nil
                ? "Radio metadata is temporarily unavailable."
                : "Couldn't refresh radio metadata."
    }

    private func metadataSignature(for info: RadioNowPlaying.SongInfo) -> String {
        [
            info.resolvedSongID ?? info.id,
            info.title ?? info.text ?? "",
            info.artist ?? "",
            info.art ?? "",
        ].joined(separator: "|")
    }

    private func prefetchArtwork(from metadata: RadioNowPlaying) {
        let urls =
            [
                metadata.nowPlaying?.song.art,
                metadata.playingNext?.song.art,
            ].compactMap { $0.flatMap(URL.init(string:)) }
            + (metadata.songHistory ?? [])
                .prefix(8)
                .compactMap { $0.song.art.flatMap(URL.init(string:)) }
        ArtworkPrefetcher.shared.prefetch(urls: urls, limit: 10, reason: "radio metadata")
    }

    private func applyUITestFixture() {
        nowPlaying = Self.uiTestNowPlaying
        refreshErrorMessage = nil
        isRefreshing = false
        lastUpdated = .now
        if let info = nowPlaying?.nowPlaying?.song {
            lastMetadataSignature = metadataSignature(for: info)
        }
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
                RadioNowPlaying.HistoryItem(
                    song: RadioNowPlaying.SongInfo(
                        id: "ui-radio-song-4",
                        art: nil,
                        text: "Bad Apple!! - Nomico",
                        artist: "Nomico",
                        title: "Bad Apple!!",
                        customFields: RadioNowPlaying.CustomFields(songID: "ui-radio-song-4")
                    )
                ),
            ]
        )
    }
}
