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
        case .listLoop: String(localized: "Repeat All")
        case .songLoop: String(localized: "Repeat One")
        case .shuffle: String(localized: "Shuffle")
        }
    }
}
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
    private var failedToEndObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failedIndices: Set<Int> = []
    private var wantsPlaybackWhenReady = true
    private var playbackGeneration = 0
    private var artworkTask: Task<Void, Never>?

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
    var canPlayNext: Bool { !queue.isEmpty && failedIndices.count < queue.count }
    var canPlayPrevious: Bool { !queue.isEmpty && failedIndices.count < queue.count }

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
        isLoading = false
        isPlaying = false
        updateNowPlayingPlaybackState()
    }

    func resume() {
        wantsPlaybackWhenReady = true
        guard let player else { return }
        player.play()
        isLoading = player.currentItem?.status != .readyToPlay
        isPlaying = player.timeControlStatus == .playing
        updateNowPlayingPlaybackState()
    }

    func playNext() {
        guard let nextIndex = nextPlayableIndex(forward: true) else { return }
        currentIndex = nextIndex
        startCurrent()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let previousIndex = nextPlayableIndex(forward: false) else { return }
        currentIndex = previousIndex
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

    private func startCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        wantsPlaybackWhenReady = true
        let song = queue[currentIndex]
        teardownPlayer()
        let generation = playbackGeneration
        currentSong = song
        playbackError = nil
        currentTime = 0
        duration = 0
        isLoading = true

        guard let url = song.audioURL else {
            handleFailure(String(localized: "This song has no playable audio."), generation: generation)
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        self.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self,
                      self.isCurrentPlayback(generation: generation, player: player, item: item)
                else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.failedIndices.remove(self.currentIndex)
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    if self.wantsPlaybackWhenReady {
                        player.play()
                        self.isPlaying = true
                    }
                    self.updateNowPlayingInfo()
                case .failed:
                    self.handleFailure(item.error?.localizedDescription ?? String(localized: "Couldn't play this song."), generation: generation)
                default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self] player, _ in
            Task { @MainActor in
                guard let self,
                      self.isCurrentPlayback(generation: generation, player: player, item: item)
                else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isLoading = false
                    self.isPlaying = true
                case .waitingToPlayAtSpecifiedRate:
                    self.isLoading = self.wantsPlaybackWhenReady
                    self.isPlaying = false
                case .paused:
                    self.isPlaying = false
                    if item.status == .readyToPlay {
                        self.isLoading = false
                    }
                @unknown default:
                    self.isPlaying = false
                }
                self.updateNowPlayingPlaybackState()
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self,
                      self.isCurrentPlayback(generation: generation, player: player, item: item)
                else { return }
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
                guard let self,
                      self.isCurrentPlayback(generation: generation, player: player, item: item)
                else { return }
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

    private func handleFailure(_ message: String, generation: Int) {
        guard generation == playbackGeneration else { return }
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
    private func randomIndex(excluding excluded: Int?) -> Int? {
        let candidates = queue.indices.filter { $0 != excluded && !failedIndices.contains($0) }
        return candidates.randomElement()
    }

    private func nextPlayableIndex(forward: Bool) -> Int? {
        guard !queue.isEmpty, failedIndices.count < queue.count else { return nil }
        if playbackMode == .shuffle {
            return randomIndex(excluding: queue.count > 1 ? currentIndex : nil)
                ?? (failedIndices.contains(currentIndex) ? nil : currentIndex)
        }

        for offset in 1 ... queue.count {
            let delta = forward ? offset : -offset
            let candidate = (currentIndex + delta + queue.count * 2) % queue.count
            if !failedIndices.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isCurrentPlayback(
        generation: Int,
        player: AVPlayer,
        item: AVPlayerItem
    ) -> Bool {
        playbackGeneration == generation
            && self.player === player
            && player.currentItem === item
    }

    private func teardownPlayer() {
        playbackGeneration &+= 1
        artworkTask?.cancel()
        artworkTask = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
        }
        failedToEndObserver = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        stalledObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

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
        artworkTask?.cancel()
        guard let url = song.thumbnailURL else { return }
        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let image = await MacImageCache.shared.image(for: url),
                  !Task.isCancelled,
                  self.currentSong?.id == song.id else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func updateNowPlayingPlaybackState() {
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = isPlaying ? .playing : (currentSong == nil ? .stopped : .paused)
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = info
    }
}
