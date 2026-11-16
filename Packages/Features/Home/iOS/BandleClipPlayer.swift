import AVFoundation
import Foundation
import Observation

/// Plays one Bandle clip at a time, outside the app's music player.
///
/// The clip shares the app's `.playback` audio session, so it would play over
/// a song. Like the video player, it pauses the app's music before it plays and
/// pauses itself when the music starts again.
@MainActor
@Observable
final class BandleClipPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var didFail = false

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var progressObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var appAudioObserver: NSObjectProtocol?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let pauseAppPlayback: @MainActor () -> Void

    init(
        player: AVPlayer = AVPlayer(),
        notificationCenter: NotificationCenter = .default,
        pauseAppPlayback: @escaping @MainActor () -> Void = { AudioPlayerManager.shared.pauseIfPlaying() }
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        self.pauseAppPlayback = pauseAppPlayback
        appAudioObserver = notificationCenter.addObserver(
            forName: MediaPlaybackCoordinator.audioWillPlay,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
        }
        progressObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(time)
            }
        }
    }

    isolated deinit {
        if let progressObserver {
            player.removeTimeObserver(progressObserver)
        }
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
        }
        if let failureObserver {
            notificationCenter.removeObserver(failureObserver)
        }
        statusObservation?.invalidate()
        if let appAudioObserver {
            notificationCenter.removeObserver(appAudioObserver)
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var playbackProgress: Double {
        get { progress }
        set { seek(to: newValue) }
    }

    func load(url: URL) {
        clearCurrentItem()
        loadedURL = url
        let item = AVPlayerItem(url: url)
        endObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishPlayback(of: item)
            }
        }
        failureObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.failPlayback(of: item)
            }
        }
        // A clip that can't be loaded (bad download, missing file) only
        // reports it through the item's status.
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.failPlayback(of: item)
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func play() {
        // A failed item can't play again; start over with a fresh one.
        if didFail || player.currentItem?.status == .failed, let loadedURL {
            load(url: loadedURL)
        }
        guard player.currentItem != nil else { return }
        if duration > 0, currentTime >= duration {
            player.seek(to: .zero)
            currentTime = 0
        }
        pauseAppPlayback()
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Pauses and rewinds, keeping the clip loaded so Play works again.
    /// A different clip replaces it through `load(url:)`.
    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }

    /// Unloads the clip, for when no clip is available.
    func unload() {
        clearCurrentItem()
    }

    func seek(to fraction: Double) {
        guard duration.isFinite, duration > 0, fraction.isFinite else { return }
        let target = duration * min(max(fraction, 0), 1)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    private func updateProgress(_ time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite, seconds >= 0 {
            currentTime = seconds
        }
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite, itemDuration >= 0
        {
            duration = itemDuration
        }
    }

    private func finishPlayback(of item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        isPlaying = false
        if duration > 0 {
            currentTime = duration
        }
    }

    private func failPlayback(of item: AVPlayerItem) {
        guard player.currentItem === item, !didFail else { return }
        DebugLogger.log("Bandle clip failed: \(item.error.map(String.init(describing:)) ?? "unknown")", category: .playback)
        player.pause()
        isPlaying = false
        didFail = true
    }

    private func clearCurrentItem() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
        }
        if let failureObserver {
            notificationCenter.removeObserver(failureObserver)
        }
        endObserver = nil
        failureObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        loadedURL = nil
        didFail = false
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
