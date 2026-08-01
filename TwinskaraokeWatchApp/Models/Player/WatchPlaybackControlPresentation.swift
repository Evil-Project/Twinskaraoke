import Foundation

nonisolated enum WatchPlaybackControlPresentation {
    static func actionLabel(songTitle: String, isLoading: Bool, isPlaying: Bool) -> String {
        if isLoading {
            return "Cancel loading \(songTitle)"
        }
        if isPlaying {
            return "Pause \(songTitle)"
        }
        return "Play \(songTitle)"
    }

    static func stateLabel(isLoading: Bool, isPlaying: Bool) -> String {
        if isLoading {
            return "Loading"
        }
        return isPlaying ? "Playing" : "Paused"
    }
}
