import Foundation

nonisolated enum MediaPlaybackEvents {
    // Retained for source compatibility; video pauses audio through the player API.
    static let videoWillPlay = Notification.Name("nk.videoWillPlay")
    static let audioWillPlay = Notification.Name("nk.audioWillPlay")
}

// Source compatibility for existing consumers.
typealias MediaPlaybackCoordinator = MediaPlaybackEvents
