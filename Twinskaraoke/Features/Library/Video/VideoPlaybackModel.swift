import Combine
import CoreMedia
import PillarboxPlayer
import SwiftUI

extension VideoQuality {
    /// Expressed as a resolution ceiling rather than a pinned variant playlist,
    /// so the player can still adapt *below* the ceiling when the connection
    /// degrades instead of stalling on a rung it cannot sustain.
    var playerLimits: PlayerLimits {
        guard let maximumResolution else { return .none }
        return PlayerLimits(preferredMaximumResolution: maximumResolution)
    }
}

/// Owns the player for the video screen.
///
/// The player lives here rather than in the view so it survives the surface
/// being torn down and rebuilt when full screen is entered or left — that is a
/// `fullScreenCover`, a separate presentation, so the `VideoView` hosting the
/// layer is recreated while playback has to continue uninterrupted.
///
/// **Picture in Picture is deliberately not supported.** Declaring it on
/// `VideoView` makes Pillarbox build PiP host views on every player publish,
/// and combined with the surface being rebuilt across the full-screen cover
/// that churned AVKit's PiP observers and could wedge playback on pause or on
/// leaving PiP. Doing it properly needs a `PictureInPictureDelegate` that
/// dismisses and restores this screen, plus a PiP button — neither of which
/// exists yet. Retaining the player without that restoration path is worse than
/// not offering PiP at all, so the declaration is omitted rather than left
/// half-wired.
///
/// `ObservableObject` rather than `@Observable` on purpose: it is paired with
/// `@StateObject`, whose autoclosure initialiser avoids building a throwaway
/// `Player` on every re-init of the view struct, which `@State` would do.
@MainActor
final class VideoPlaybackModel: ObservableObject {
    let player = Player(configuration: .videoGallery)

    /// The video currently loaded, so a re-entered screen does not reload the
    /// item it is already playing.
    private(set) var video: GalleryVideo?

    /// The position a fresh load resumed from, for the screen's resume banner.
    /// Cleared once the viewer acts on it or it times out.
    @Published private(set) var resumedFrom: TimeInterval?

    var quality: VideoQuality = .auto {
        didSet {
            guard quality != oldValue else { return }
            player.limits = quality.playerLimits
        }
    }

    /// How often the playhead is written while playing.
    ///
    /// The explicit saves (leaving the screen, backgrounding) cover the ordinary
    /// exits; this covers being killed in the background, where nothing runs.
    private static let saveInterval: Duration = .seconds(5)

    /// How long the resume banner stays up before dismissing itself.
    private static let resumeBannerDuration: Duration = .seconds(6)

    /// Runtime as the player measures it.
    ///
    /// `GalleryVideo.duration` is unusable here: it is 0 or absent for ~1279 of
    /// the ~1385 catalogue items and is never set for the watchalongs.
    private var duration: TimeInterval = 0

    /// Whether the playhead has been seen advancing on the loaded item.
    ///
    /// Positions are only worth recording once this is true. A sample taken
    /// between `player.items` being assigned and the resume seek landing reads
    /// as zero, and `VideoResumeStore.record` treats a near-zero position as
    /// "start over" — so persisting eagerly would delete the very entry the
    /// pending seek is about to use.
    private var hasObservedPlayback = false

    private var saveTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        player.propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.apply(properties)
            }
            .store(in: &cancellables)
    }

    isolated deinit {
        saveTask?.cancel()
        bannerTask?.cancel()
    }

    /// Loads `video`, unless it is already the loaded one.
    ///
    /// - Returns: `true` when a new item was loaded, so the caller can decide
    ///   whether to start playback and re-run its entry animation.
    @discardableResult
    func load(_ video: GalleryVideo) -> Bool {
        guard self.video?.id != video.id else { return false }
        self.video = video
        hasObservedPlayback = false
        duration = 0
        resumedFrom = nil
        bannerTask?.cancel()

        guard let url = video.streamURL else {
            player.removeAllItems()
            return false
        }

        let resumePoint = VideoResumeStore.shared.point(for: video.id)
        player.limits = quality.playerLimits
        player.items = [
            .simple(
                url: url,
                metadata: PlayerMetadata(
                    title: video.displayTitle,
                    subtitle: video.createdBy,
                    description: video.description,
                    imageSource: video.posterURL.map { .url(standardResolution: $0) } ?? .none
                ),
                configuration: Self.playbackConfiguration(resumingFrom: resumePoint)
            ),
        ]
        if let resumePoint {
            showResumeBanner(at: resumePoint.position)
        }
        return true
    }

    /// Reloads the current video from scratch, for the error state's retry.
    ///
    /// Goes back through `load`, so a retry picks the resume point up again
    /// rather than restarting a video the viewer was halfway through.
    func reload() {
        guard let video else { return }
        self.video = nil
        load(video)
        play()
    }

    func play() {
        player.becomeActive()
        player.play()
        startPersisting()
    }

    func pause() {
        player.pause()
        persistPosition()
        saveTask?.cancel()
        saveTask = nil
    }

    /// Restarts the current video and forgets where it had got to.
    func startFromBeginning() {
        dismissResumeBanner()
        guard let video else { return }
        VideoResumeStore.shared.clear(videoID: video.id)
        player.seek(to: .zero)
        player.play()
    }

    func dismissResumeBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        resumedFrom = nil
    }

    /// Writes the playhead to the resume store.
    ///
    /// Called on the save cadence and at every point the screen can go away:
    /// leaving it, backgrounding, and — via the cadence — being killed while
    /// backgrounded.
    func persistPosition() {
        guard let video, hasObservedPlayback else { return }
        let time = player.time()
        guard time.isNumeric else { return }
        VideoResumeStore.shared.record(video, position: time.seconds, duration: duration)
    }

    // MARK: - Player observation

    private func apply(_ properties: PlayerProperties) {
        let measured = properties.seekableTimeRange.duration.seconds
        // Never let an unknown range clobber a runtime already established:
        // `seekableTimeRange` is `.invalid` — and so NaN in seconds — until the
        // item has loaded, and again briefly across a quality change.
        if measured.isFinite, measured > 0 {
            duration = measured
        }

        switch properties.playbackState {
        case .playing:
            // The playhead can only be trusted once the item is actually
            // rendering, which is after any resume seek has landed.
            hasObservedPlayback = true
        case .ended:
            // Watched: off the shelf, badged in the gallery, and a re-open
            // starts over. The store would reach the same conclusion from the
            // position, but only if a save happened to land in the final
            // seconds — which the 5s cadence cannot promise.
            if let video {
                VideoResumeStore.shared.markWatched(video.id)
            }
            hasObservedPlayback = false
        case .idle, .paused:
            break
        }
    }

    // MARK: - Save cadence

    private func startPersisting() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.saveInterval)
                guard !Task.isCancelled, let self else { return }
                persistPosition()
            }
        }
    }

    private func showResumeBanner(at position: TimeInterval) {
        resumedFrom = position
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeBannerDuration)
            guard !Task.isCancelled else { return }
            self?.resumedFrom = nil
        }
    }

    /// Resumes at the stored position, biased to land at or *before* it.
    ///
    /// `before` rather than `at`: an exact seek makes the decoder walk from the
    /// preceding keyframe, which shows up as a stall on entry, and overshooting
    /// a resume point skips content the viewer has not seen.
    private static func playbackConfiguration(resumingFrom point: VideoResumePoint?) -> PlaybackConfiguration {
        guard let point, point.position > 0 else { return .default }
        return PlaybackConfiguration(
            position: before(CMTime(seconds: point.position, preferredTimescale: 600))
        )
    }
}

extension PlayerConfiguration {
    /// Gallery videos are on-demand, so the only behaviour worth stating is the
    /// skip interval and that AirPlay is allowed. Everything else is Pillarbox's
    /// default.
    static let videoGallery = PlayerConfiguration(
        allowsExternalPlayback: true,
        usesExternalPlaybackWhileMirroring: false,
        backwardSkipInterval: 10,
        forwardSkipInterval: 10
    )
}
