import Combine
import CoreMedia
import PillarboxPlayer
import SwiftUI

extension VideoQuality {
    var playerLimits: PlayerLimits {
        guard let maximumResolution else { return .none }
        return PlayerLimits(preferredMaximumResolution: maximumResolution)
    }
}
@MainActor
final class VideoPlaybackModel: ObservableObject {
    let player = Player(configuration: .videoGallery)
    private(set) var video: GalleryVideo?
    @Published private(set) var resumedFrom: TimeInterval?

    var quality: VideoQuality = .auto {
        didSet {
            guard quality != oldValue else { return }
            player.limits = quality.playerLimits
        }
    }
    private static let saveInterval: Duration = .seconds(5)
    private static let resumeBannerDuration: Duration = .seconds(6)
    private var duration: TimeInterval = 0
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
    func startFromBeginning() {
        dismissResumeBanner()
        guard let video else { return }
        VideoResumeStore.shared.clear(videoID: video.id)
        player.seek(to: .zero)
        play()
    }

    func dismissResumeBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        resumedFrom = nil
    }
    func persistPosition() {
        guard let video, hasObservedPlayback else { return }
        let time = player.time()
        guard time.isNumeric else { return }
        VideoResumeStore.shared.record(video, position: time.seconds, duration: duration)
    }

    private func apply(_ properties: PlayerProperties) {
        let measured = properties.seekableTimeRange.duration.seconds
        if measured.isFinite, measured > 0 {
            duration = measured
        }

        switch properties.playbackState {
        case .playing:
            hasObservedPlayback = true
        case .ended:
            if let video {
                VideoResumeStore.shared.markWatched(video.id)
            }
            hasObservedPlayback = false
        case .idle, .paused:
            break
        }
    }

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
    private static func playbackConfiguration(resumingFrom point: VideoResumePoint?) -> PlaybackConfiguration {
        guard let point, point.position > 0 else { return .default }
        return PlaybackConfiguration(
            position: before(CMTime(seconds: point.position, preferredTimescale: 600))
        )
    }
}

extension PlayerConfiguration {
    static let videoGallery = PlayerConfiguration(
        allowsExternalPlayback: true,
        usesExternalPlaybackWhileMirroring: false,
        backwardSkipInterval: 10,
        forwardSkipInterval: 10
    )
}
