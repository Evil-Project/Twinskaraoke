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

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var progressObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
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
        player.replaceCurrentItem(with: item)
    }

    func play() {
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

    private func clearCurrentItem() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
        }
        endObserver = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
