import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftUI

enum MacPlaybackMode: String, CaseIterable {
    case listLoop
    case songLoop
    case shuffle

    var iconName: String {
        switch self {
        case .listLoop: "repeat"
        case .songLoop: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    var label: String {
        switch self {
        case .listLoop: "Repeat All"
        case .songLoop: "Repeat One"
        case .shuffle: "Shuffle"
        }
    }
}

/// Playback for the Mac app.
///
/// Deliberately not a port of the tvOS `AudioManager`: everything here that
/// differs from that file is because `AVAudioSession` does not exist on macOS.
/// There is no category to set, no session to activate, and no interruption
/// notification — the system mixes and ducks apps itself. What survives the
/// platform change is `AVPlayer` plus the `MediaPlayer` now-playing/remote
/// command surface, both of which are fully supported natively.
@MainActor
@Observable
final class MacAudioManager {
    static let shared = MacAudioManager()

    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var playbackError: String?
    var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var queue: [Song] = []
    private(set) var currentIndex = 0
    var playbackMode: MacPlaybackMode = .listLoop
    var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    /// Indices that failed to load, so a broken queue can't spin forever.
    private var failedIndices: Set<Int> = []
    /// Whether playback should begin once the item becomes ready. A pause
    /// issued while still loading used to be overwritten by the unconditional
    /// `play()` in the `.readyToPlay` observer.
    private var wantsPlaybackWhenReady = true

    private init() {
        configureRemoteCommands()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    // Once every index has failed there is nothing left to advance to, so the
    // transport buttons should stop pretending otherwise.
    var canPlayNext: Bool { !queue.isEmpty && failedIndices.count < queue.count }
    var canPlayPrevious: Bool { !queue.isEmpty && failedIndices.count < queue.count }

    // MARK: - Transport

    func play(song: Song, context: [Song] = []) {
        var playbackQueue = context.isEmpty ? [song] : context
        if !playbackQueue.contains(where: { $0.id == song.id }) {
            playbackQueue.insert(song, at: 0)
        }
        let index = playbackQueue.firstIndex { $0.id == song.id } ?? 0
        queue = playbackQueue
        currentIndex = index
        failedIndices.removeAll()
        startCurrent()
    }

    func togglePlayPause() {
        guard player != nil else {
            if let song = currentSong { play(song: song, context: queue) }
            return
        }
        isPlaying ? pause() : resume()
    }

    func pause() {
        wantsPlaybackWhenReady = false
        player?.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
    }

    func resume() {
        wantsPlaybackWhenReady = true
        guard let player else { return }
        player.play()
        isPlaying = true
        updateNowPlayingPlaybackState()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        switch playbackMode {
        case .shuffle:
            currentIndex = randomIndex(excluding: queue.count > 1 ? currentIndex : nil)
        case .listLoop, .songLoop:
            currentIndex = (currentIndex + 1) % queue.count
        }
        startCurrent()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        // Match the platform convention: past ~3s, restart the track instead
        // of leaving the song.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        currentIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
        startCurrent()
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let clamped = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] finished in
            Task { @MainActor in
                guard finished, let self, self.player === player else { return }
                self.currentTime = clamped
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    func cycleMode() {
        let modes = MacPlaybackMode.allCases
        let next = (modes.firstIndex(of: playbackMode).map { $0 + 1 } ?? 0) % modes.count
        playbackMode = modes[next]
    }

    // MARK: - Loading

    private func startCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        wantsPlaybackWhenReady = true
        let song = queue[currentIndex]
        currentSong = song
        playbackError = nil

        teardownPlayer()
        currentTime = 0
        duration = 0

        guard let url = song.audioURL else {
            handleFailure("This song has no playable audio.")
            return
        }

        isLoading = true

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        self.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player === player else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.failedIndices.remove(self.currentIndex)
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    // Honour a pause the user issued while this was loading.
                    if self.wantsPlaybackWhenReady {
                        player.play()
                        self.isPlaying = true
                    }
                    self.updateNowPlayingInfo()
                case .failed:
                    self.handleFailure(item.error?.localizedDescription ?? "Couldn't play this song.")
                default:
                    break
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.player === player else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if self.duration == 0, let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === player else { return }
                self.handleReachedEnd()
            }
        }
    }

    private func handleReachedEnd() {
        if playbackMode == .songLoop {
            seek(to: 0)
            resume()
            return
        }
        playNext()
    }

    private func handleFailure(_ message: String) {
        isLoading = false
        isPlaying = false
        playbackError = message
        failedIndices.insert(currentIndex)
        // Every remaining track failed — stop instead of cycling the queue.
        guard failedIndices.count < queue.count, queue.count > 1 else {
            teardownPlayer()
            updateNowPlayingPlaybackState()
            return
        }
        // Yield between invalid items instead of recursively exhausting a
        // potentially large queue on one stack. Ignore superseded failures.
        let failedSong = currentSong?.id
        let failedIndex = currentIndex
        Task { @MainActor [weak self] in
            guard let self, self.currentSong?.id == failedSong,
                  self.currentIndex == failedIndex, self.playbackError != nil,
                  self.wantsPlaybackWhenReady else { return }
            self.playNext()
        }
    }

    /// Avoid revisiting failed indices while searching for playable audio.
    private func randomIndex(excluding excluded: Int?) -> Int {
        let candidates = queue.indices.filter { $0 != excluded && !failedIndices.contains($0) }
        if let pick = candidates.randomElement() { return pick }
        // Nothing unplayed left: fall back to any index other than the current
        // one so the caller's own exhaustion guard can end the walk.
        return queue.indices.filter { $0 != excluded }.randomElement() ?? currentIndex
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        let artist = song.displayArtist
        if !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        loadNowPlayingArtwork(for: song)
    }

    private func loadNowPlayingArtwork(for song: Song) {
        guard let url = song.thumbnailURL else { return }
        Task { @MainActor in
            guard let image = await MacImageCache.shared.image(for: url),
                  currentSong?.id == song.id else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func updateNowPlayingPlaybackState() {
        let center = MPNowPlayingInfoCenter.default()
        // macOS drives the system Now Playing panel and the media keys from
        // playbackState, not from the playback rate in nowPlayingInfo — unlike
        // iOS, where the rate alone is enough.
        center.playbackState = isPlaying ? .playing : (currentSong == nil ? .stopped : .paused)
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = info
    }
}
