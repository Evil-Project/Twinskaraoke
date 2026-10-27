import Foundation

nonisolated enum AutoplaySelection {
    /// Preserve the server's recommendation order while excluding the song
    /// that just ended, duplicates, and entries without a playable source.
    static func playableSongs(_ candidates: [Song], excluding songID: String?) -> [Song] {
        var seen = Set<String>()
        return candidates.filter {
            $0.id != songID && $0.audioURL != nil && seen.insert($0.id).inserted
        }
    }
}
