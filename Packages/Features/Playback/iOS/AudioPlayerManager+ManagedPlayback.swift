import AVFoundation
import Foundation

enum ManagedAVPlayerKind {
    case radio, stream
}

extension AudioPlayerManager {
    func startAirPlaySong(_ url: URL, position: TimeInterval) {
        cancelPendingTransitionWork()
        loadedEngine?.stop()
        let player = AirPlaySongComparison.makePlayer(url: url)
        guard let item = player.currentItem else { return }
        streamPlayer = player
        streamPlaybackRequested = true
        setPreferredStreamResumeTime(position, for: currentSong?.id)
        setPlaybackState(playing: false, buffering: true, reloadArtwork: true, reason: "airPlaySong")
        observeAirPlayItem(item, on: player)
        seekAirPlayPlayer(player, to: position, autoplay: true)
    }

    private func observeAirPlayItem(_ item: AVPlayerItem, on player: AVQueuePlayer) {
        observeManagedPlayer(player, item: item, kind: .stream)
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak player, weak item] _ in
            Task { @MainActor in
                guard let self, let player, let item, self.streamPlayer === player, player.currentItem === item,
                      self.streamPlaybackRequested, self.airPlayTimeline.pendingPosition == nil else { return }
                self.promoteAirPlayTransition(at: player.currentTime().seconds)
                if self.handlePrematurePlaybackEndIfNeeded(source: "AirPlay") { return }
                if self.sleepTimer.consumeEndOfSong() { self.pauseCurrentPlayback(source: "airPlaySong.endOfSong") }
                else {
                    self.streamPlaybackRequested = false
                    self.playNextOrRandom()
                }
            }
        }
    }

    func replaceAirPlayItem(_ item: AVPlayerItem, on player: AVQueuePlayer, position: TimeInterval, autoplay: Bool) {
        player.pause()
        streamPlayerCancellables.removeAll()
        if let observer = streamEndObserver { NotificationCenter.default.removeObserver(observer) }
        player.removeAllItems()
        player.insert(item, after: nil)
        observeAirPlayItem(item, on: player)
        seekAirPlayPlayer(player, to: position, autoplay: autoplay)
    }

    func seekAirPlayPlayer(_ player: AVQueuePlayer, to position: TimeInterval, autoplay: Bool) {
        if autoplay { armAirPlayStartupTimeout(for: player) }
        airPlayTimeline.seek(player, to: position) { [weak self, weak player] finished in
            guard let self, let player, self.streamPlayer === player else { return }
            if autoplay, self.streamPlaybackRequested {
                if finished { player.play() }
                else if let item = player.currentItem { self.handleManagedPlayerFailure(player: player, item: item, kind: .stream) }
            }
            guard self.streamPlayer === player else { return }
            let time = self.airPlayTimeline.songTime(player.currentTime().seconds)
            if time.isFinite {
                self.lastKnownPlaybackTime = time
                self.progress = self.playbackDuration > 0 ? min(1, time / self.playbackDuration) : 0
            }
            self.clearPreferredStreamResumeTime()
            self.updateNowPlayingInfo(reloadArtwork: false)
            self.scheduleSessionSave()
        }
    }

    func armAirPlayStartupTimeout(for player: AVQueuePlayer) {
        airPlayTimeline.armStartupTimeout { [weak self, weak player] in
            guard let self, let player, self.streamPlayer === player, self.streamPlaybackRequested,
                  player.timeControlStatus != .playing, let item = player.currentItem else { return }
            self.handleManagedPlayerFailure(player: player, item: item, kind: .stream)
        }
    }

    func discardAirPlayTransition() {
        guard let player = streamPlayer as? AVQueuePlayer, let url = currentPlaybackURL else { return }
        let position = activePlaybackTime()
        airPlayTimeline.reset()
        replaceAirPlayItem(AVPlayerItem(url: url), on: player, position: position, autoplay: streamPlaybackRequested)
    }

    func promoteAirPlayTransition(at time: TimeInterval) {
        guard let prepared = airPlayTimeline.transition, time >= prepared.timing.promotionTime,
              let plan = airPlayTimeline.promote() else { return }
        finishTrackTransition(plan, preservingAirPlayPlayer: true)
    }

    func observeManagedPlayer(
        _ player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        let statusHandler: (AVPlayerItem.Status) -> Void = { [weak self, weak player, weak item] status in
            guard let self, let player, let item else { return }
            handleManagedItemStatus(status, player: player, item: item, kind: kind)
        }
        let stateHandler: () -> Void = { [weak self, weak player] in
            guard let self, let player else { return }
            refreshManagedPlayerState(player, kind: kind)
        }

        let observations = ManagedAVPlayerObservation.observe(player: player, item: item, onStatus: statusHandler, onState: stateHandler)
        switch kind {
        case .radio: radioPlayerCancellables = observations
        case .stream: streamPlayerCancellables = observations
        }
    }

    private func handleManagedItemStatus(
        _ status: AVPlayerItem.Status,
        player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        guard isCurrentManagedPlayer(player, kind: kind), player.currentItem === item else { return }
        switch status {
        case .readyToPlay:
            refreshManagedPlayerState(player, kind: kind)
        case .failed:
            handleManagedPlayerFailure(player: player, item: item, kind: kind)
        case .unknown:
            refreshManagedPlayerState(player, kind: kind)
        @unknown default:
            refreshManagedPlayerState(player, kind: kind)
        }
    }

    func refreshManagedPlayerState(_ player: AVPlayer, kind: ManagedAVPlayerKind) {
        guard isCurrentManagedPlayer(player, kind: kind) else { return }
        guard let item = player.currentItem else {
            setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).noItem")
            return
        }
        if item.status == .failed {
            handleManagedPlayerFailure(player: player, item: item, kind: kind)
            return
        }
        let playbackRequested = playbackRequested(for: kind)
        guard playbackRequested else {
            setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).notRequested")
            return
        }
        if player.timeControlStatus == .playing {
            if player is AVQueuePlayer, airPlayTimeline.pendingPosition == nil { airPlayTimeline.cancelStartupTimeout() }
            setPlaybackState(playing: true, buffering: false, reason: "managed.\(kind).playing")
        } else {
            setPlaybackState(playing: false, buffering: true, reason: "managed.\(kind).buffering")
        }
    }

    func handleManagedPlayerFailure(
        player: AVPlayer,
        item: AVPlayerItem,
        kind: ManagedAVPlayerKind
    ) {
        guard isCurrentManagedPlayer(player, kind: kind), player.currentItem === item else { return }
        if player is AVQueuePlayer {
            lastKnownPlaybackTime = activePlaybackTime()
            stopStreamPlayer()
            clearPreferredStreamResumeTime()
            cancelPendingTransitionWork()
            reportLoadFailure(.unavailable)
        }
        let message = item.error?.localizedDescription
            ?? player.error?.localizedDescription
            ?? "unknown error"
        switch kind {
        case .radio:
            DebugLogger.log("Radio AVPlayer failed: \(message)", category: .playback)
            radioPlaybackRequested = false
        case .stream:
            DebugLogger.log("Stream AVPlayer failed: \(message)", category: .playback)
            streamPlaybackRequested = false
        }
        setPlaybackState(playing: false, buffering: false, reason: "managed.\(kind).failure")
    }

    private func isCurrentManagedPlayer(_ player: AVPlayer, kind: ManagedAVPlayerKind) -> Bool {
        switch kind {
        case .radio:
            radioPlayer === player
        case .stream:
            streamPlayer === player
        }
    }

    private func playbackRequested(for kind: ManagedAVPlayerKind) -> Bool {
        switch kind {
        case .radio:
            radioPlaybackRequested
        case .stream:
            streamPlaybackRequested
        }
    }

    @discardableResult
    func reconcileAirPlayRoute(resuming: Bool = false) -> Bool {
        guard AirPlaySongComparison.isEnabled, phoneAudioAllowed, !isRadioMode, !isRemotePlaybackCaching,
              let url = currentPlaybackURL, url.isFileURL else { return false }
        let useAirPlay = AirPlaySongComparison.shouldUsePlayer(
            outputs: AirPlaySongComparison.outputs, url: url, processingActive: anyAIEffectActive || eqEnabled
        )
        guard useAirPlay != (streamPlayer is AVQueuePlayer) || airPlayHandoffs.isPending else { return false }
        let position = activePlaybackTime()
        let autoplay = resuming || isPlaybackRequested
        let songID = currentSong?.id
        stopStreamPlayer()
        cancelPendingTransitionWork()
        loadedEngine?.stop()
        lastKnownPlaybackTime = position
        clearPreferredStreamResumeTime()
        guard autoplay else { return true }
        let request = airPlayHandoffs.begin()
        let restart: @MainActor () -> Void = { [weak self] in
            guard let self, self.airPlayHandoffs.isCurrent(request), self.currentSong?.id == songID,
                  self.currentPlaybackURL == url else { return }
            self.airPlayHandoffs.invalidate()
            self.startPlayingFile(url, startAt: position, resetSeparation: false)
            if self.anyAIEffectActive { self.applyMLSeparationIfNeeded() }
        }
        if audioSessionController.performWhenReady(restart, replacingPending: true) { restart() }
        return true
    }
}
