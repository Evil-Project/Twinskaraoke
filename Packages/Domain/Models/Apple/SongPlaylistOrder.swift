import Foundation

extension [Song] {
    /// The songs in their playlist's order: by each song's `order`, the place
    /// the server keeps for it. Songs without one keep their relative position,
    /// after the rest.
    ///
    /// Playlist routes send songs in no particular order (a setlist arrives as
    /// 14, 12, 7, 3, …), so every decoder that reads a playlist's songs sorts
    /// them this way. Stable, so tied songs keep the server's arrangement.
    nonisolated func inPlaylistOrder() -> [Song] {
        enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.order ?? Int.max
                let right = rhs.element.order ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
