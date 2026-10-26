import Observation

@MainActor
@Observable
final class PlaybackClock {
    static let shared = PlaybackClock()

    var progress: Double = 0

    private init() {}
}
