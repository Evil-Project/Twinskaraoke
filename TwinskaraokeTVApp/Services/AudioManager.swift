import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

enum PlaybackMode {
    case listLoop
    case singleLoop

    var iconName: String {
        switch self {
        case .listLoop: "repeat"
        case .singleLoop: "repeat.1"
        }
    }
}

/// Streaming audio playback for the tvOS app. The Apple TV is always online, so
/// unlike the watch target this streams directly through `AVPlayer` rather than
/// downloading to a local cache first. It still drives the queue, Now Playing
/// info, and the Siri Remote / Control Center transport commands.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var currentSong: Song? {
        didSet { refreshUpNext() }
    }
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Song] = [] {
        didSet { refreshUpNext() }
    }
    @Published var currentIndex: Int = 0 {
        didSet { refreshUpNext() }
    }
    @Published private(set) var upNextSongs: [Song] = []
    @Published var playbackMode: PlaybackMode = .listLoop
    @Published var isShuffleOn = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var playbackRequested = false
    private var shouldResumeAfterInterruption = false

    private init() {
        configureAudioSession()
        setupRemoteCommands()
        setupInterruptionHandler()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Queue

    private func refreshUpNext() {
        guard let index = resolvedCurrentQueueIndex else {
            upNextSongs = []
            return
        }
        let nextIndex = index + 1
        guard nextIndex < queue.endIndex else {
            upNextSongs = []
            return
        }
        upNextSongs = Array(queue[nextIndex...])
    }

    private var resolvedCurrentQueueIndex: Int? {
        guard !queue.isEmpty, let currentSong else { return nil }
        if queue.indices.contains(currentIndex), queue[currentIndex] == currentSong {
            return currentIndex
        }
        return queue.firstIndex(of: currentSong)
    }

    // MARK: - Playback control

    func play(song: Song, context: [Song] = []) {
        var playbackQueue = context.isEmpty ? [song] : context
        if let index = playbackQueue.firstIndex(of: song) {
            currentIndex = index
        } else {
            playbackQueue.insert(song, at: 0)
            currentIndex = 0
        }
        queue = playbackQueue
        currentSong = song
        prepareAndPlay()
    }

    private func prepareAndPlay() {
        cleanupPlayer()
        currentTime = 0
        duration = 0
        isPlaying = false
        playbackRequested = true
        cancellables.removeAll()
        setupInterruptionHandler()

        guard let song = currentSong, let url = song.audioURL else {
            playbackRequested = false
            isLoading = false
            return
        }
        isLoading = true
        setupPlayer(with: url)
    }

    private func setupPlayer(with url: URL) {
        activateAudioSession()
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                let seconds = CMTimeGetSeconds(dur)
                if !seconds.isNaN, seconds > 0 {
                    self?.duration = seconds
                }
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    if playbackRequested { player.play() }
                    refreshPlaybackState()
                    updateNowPlayingInfo()
                } else if status == .failed {
                    isLoading = false
                    isPlaying = false
                    playbackRequested = false
                    playNext()
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlaybackState() }
            .store(in: &cancellables)

        // 0.1s rather than 0.5s: `currentTime` is what drives lyric highlighting,
        // and at half-second granularity a line could light up a beat late.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite, !seconds.isNaN {
                    currentTime = max(0, seconds)
                }
            }
        }

        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.playEnded() }
        }
    }

    private func refreshPlaybackState() {
        guard playbackRequested, let player else {
            isPlaying = false
            return
        }
        if player.timeControlStatus == .playing {
            isPlaying = true
            isLoading = false
        } else {
            isPlaying = false
            isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        }
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        if playbackRequested || isPlaying {
            return pausePlayback()
        }
        return resumePlayback()
    }

    @discardableResult
    private func pausePlayback() -> Bool {
        guard player != nil || playbackRequested || isLoading else { return false }
        playbackRequested = false
        player?.pause()
        isPlaying = false
        isLoading = false
        updateNowPlayingInfo()
        return true
    }

    @discardableResult
    private func resumePlayback() -> Bool {
        guard let player else {
            if currentSong != nil {
                prepareAndPlay()
                return true
            }
            return false
        }
        activateAudioSession()
        playbackRequested = true
        player.play()
        refreshPlaybackState()
        updateNowPlayingInfo()
        return true
    }

    func playNext() {
        playNextOrRandom()
    }

    func playNextOrRandom() {
        guard !queue.isEmpty else { return }
        currentIndex = resolvedCurrentQueueIndex ?? queue.startIndex
        if isShuffleOn, queue.count > 1 {
            var nextIndex = currentIndex
            while nextIndex == currentIndex {
                nextIndex = Int.random(in: 0 ..< queue.count)
            }
            currentIndex = nextIndex
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }
        currentSong = queue[currentIndex]
        prepareAndPlay()
    }

    func playPrevious() {
        if currentTime > 3.0 {
            player?.seek(to: .zero)
            return
        }
        guard !queue.isEmpty else {
            player?.seek(to: .zero)
            return
        }
        if let index = resolvedCurrentQueueIndex { currentIndex = index }
        if currentIndex > 0 {
            currentIndex -= 1
            currentSong = queue[currentIndex]
            prepareAndPlay()
        } else {
            player?.seek(to: .zero)
        }
    }

    private func playEnded() {
        if playbackMode == .singleLoop {
            let loopingPlayer = player
            loopingPlayer?.seek(to: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.player === loopingPlayer,
                          self.playbackRequested
                    else { return }
                    loopingPlayer?.play()
                }
            }
        } else {
            playNextOrRandom()
        }
    }

    func toggleMode() {
        playbackMode = playbackMode == .listLoop ? .singleLoop : .listLoop
    }

    func toggleShuffle() {
        isShuffleOn.toggle()
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        updateNowPlayingInfo()
    }

    // MARK: - Session & remote commands

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, policy: .longFormAudio
        )
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupInterruptionHandler() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            shouldResumeAfterInterruption = playbackRequested
            if playbackRequested {
                player?.pause()
                isPlaying = false
            }
        case .ended:
            guard let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsValue)
            if opts.contains(.shouldResume), shouldResumeAfterInterruption {
                resumePlayback()
            }
            shouldResumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        func onMain(
            _ action: @escaping @MainActor () -> MPRemoteCommandHandlerStatus
        ) -> MPRemoteCommandHandlerStatus {
            if Thread.isMainThread {
                return MainActor.assumeIsolated { action() }
            }
            var status: MPRemoteCommandHandlerStatus = .commandFailed
            DispatchQueue.main.sync { status = MainActor.assumeIsolated { action() } }
            return status
        }

        let play = cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return onMain { self.resumePlayback() ? .success : .commandFailed }
        }
        remoteCommandTargets.append((cc.playCommand, play))

        let pause = cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return onMain { self.pausePlayback() ? .success : .commandFailed }
        }
        remoteCommandTargets.append((cc.pauseCommand, pause))

        let toggle = cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return onMain { self.togglePlayPause() ? .success : .commandFailed }
        }
        remoteCommandTargets.append((cc.togglePlayPauseCommand, toggle))

        let next = cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return onMain { self.playNextOrRandom(); return .success }
        }
        remoteCommandTargets.append((cc.nextTrackCommand, next))

        let previous = cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return onMain { self.playPrevious(); return .success }
        }
        remoteCommandTargets.append((cc.previousTrackCommand, previous))

        cc.changePlaybackPositionCommand.isEnabled = true
        let scrub = cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            return onMain { self.seek(to: event.positionTime); return .success }
        }
        remoteCommandTargets.append((cc.changePlaybackPositionCommand, scrub))
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artistName
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let artwork = nowPlayingArtwork(for: song) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func nowPlayingArtwork(for song: Song) -> MPMediaItemArtwork? {
        guard let url = song.heroImageURL else { return nil }
        if let image = TVImageCache.shared.cachedImage(for: url) {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        Task { [weak self] in
            guard let self,
                  await TVImageCache.shared.image(for: url) != nil,
                  self.currentSong?.id == song.id
            else { return }
            self.updateNowPlayingInfo()
        }
        return nil
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        player?.pause()
        player = nil
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for target in remoteCommandTargets {
            target.command.removeTarget(target.target)
        }
        player?.pause()
    }
}
