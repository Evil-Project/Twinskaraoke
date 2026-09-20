import Foundation
import Observation
@MainActor
@Observable
final class RadioController {
    static let shared = RadioController()

    private(set) var nowPlaying: RadioNowPlaying?
    private(set) var isRefreshing = false
    private(set) var refreshErrorMessage: String?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var lastMetadataSignature: String?
    private var isScreenVisible = false
    private let pollInterval: Duration = .seconds(15)

    private init() {}

    func start() {
        isScreenVisible = true
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
            refreshErrorMessage = nowPlaying == nil
                ? String(localized: "Radio is temporarily unavailable.")
                : String(localized: "Couldn't refresh what's playing.")
        }
    }
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

}
