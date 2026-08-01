import Foundation

nonisolated enum WatchQueuePresentation {
    static func summary(
        upNextSongs: [Song],
        queueCount: Int,
        playbackMode: PlaybackMode
    ) -> String {
        guard !upNextSongs.isEmpty else {
            return continuationText(queueCount: queueCount, playbackMode: playbackMode)
        }

        let countText = upNextSongs.count == 1
            ? "1 song next"
            : "\(upNextSongs.count) songs next"
        return "\(countText) - \(durationText(for: upNextSongs))"
    }

    static func emptyState(
        queueCount: Int,
        playbackMode: PlaybackMode
    ) -> (title: String, message: String) {
        if playbackMode == .singleLoop || queueCount == 1 {
            return ("Repeat One", "This song plays again.")
        }
        return ("Repeating Queue", "The first song plays next.")
    }

    static func accessibilityValue(
        upNextCount: Int,
        queueCount: Int,
        playbackMode: PlaybackMode
    ) -> String {
        if upNextCount == 1 {
            return "1 song queued"
        }
        if upNextCount > 1 {
            return "\(upNextCount) songs queued"
        }
        if queueCount == 0 {
            return "No songs queued"
        }
        if playbackMode == .singleLoop || queueCount == 1 {
            return "Current song repeats"
        }
        return "Queue repeats from beginning"
    }

    private static func continuationText(
        queueCount: Int,
        playbackMode: PlaybackMode
    ) -> String {
        if playbackMode == .singleLoop || queueCount == 1 {
            return "Repeats this song"
        }
        return "Repeats from beginning"
    }

    private static func durationText(for songs: [Song]) -> String {
        let totalSeconds = songs.reduce(0) { $0 + max(0, $1.duration) }
        guard totalSeconds > 0 else { return "0:00" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
