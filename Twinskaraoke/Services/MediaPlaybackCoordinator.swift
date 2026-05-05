import Foundation

/// Coordinates exclusive playback between the audio engine (`AudioPlayerManager`)
/// and the video player. Whichever surface posts here, the other listens and
/// pauses itself.
enum MediaPlaybackCoordinator {
  static let audioWillPlay = Notification.Name("nk.audioWillPlay")
  static let videoWillPlay = Notification.Name("nk.videoWillPlay")
}
