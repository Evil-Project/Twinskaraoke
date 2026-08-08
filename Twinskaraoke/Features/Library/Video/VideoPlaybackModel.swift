import Combine
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

    var quality: VideoQuality = .auto {
        didSet {
            guard quality != oldValue else { return }
            player.limits = quality.playerLimits
        }
    }

    /// Loads `video`, unless it is already the loaded one.
    ///
    /// - Returns: `true` when a new item was loaded, so the caller can decide
    ///   whether to start playback and re-run its entry animation.
    @discardableResult
    func load(_ video: GalleryVideo) -> Bool {
        guard self.video?.id != video.id else { return false }
        self.video = video

        guard let url = video.streamURL else {
            player.removeAllItems()
            return false
        }
        player.limits = quality.playerLimits
        player.items = [
            .simple(
                url: url,
                metadata: PlayerMetadata(
                    title: video.displayTitle,
                    subtitle: video.createdBy,
                    description: video.description,
                    imageSource: video.posterURL.map { .url(standardResolution: $0) } ?? .none
                )
            ),
        ]
        return true
    }

    /// Reloads the current video from scratch, for the error state's retry.
    func reload() {
        guard let video else { return }
        self.video = nil
        load(video)
        play()
    }

    func play() {
        player.becomeActive()
        player.play()
    }

    func pause() {
        player.pause()
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
