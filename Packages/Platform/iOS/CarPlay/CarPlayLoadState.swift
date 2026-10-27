import Foundation

/// Stored independently of content so playback updates cannot turn a request
/// failure or an in-flight request into a successful empty result.
enum CarPlayLoadState: Equatable {
    case loading
    case loaded
    case failed
}
