import Foundation

/// Resolves queue positions without treating a song ID as a unique queue entry.
/// A tracked index always wins; value matching is only a fallback for direct
/// selections that do not carry an occurrence index.
nonisolated enum QueueOccurrenceNavigator {
    struct Selection: Sendable {
        let index: Int
        let song: Song
    }

    static func resolvedIndex(
        for song: Song,
        in queue: [Song],
        preferredIndex: Int? = nil,
        after currentIndex: Int? = nil,
        preferFollowingMatch: Bool = false
    ) -> Int? {
        if let preferredIndex,
           queue.indices.contains(preferredIndex),
           queue[preferredIndex].id == song.id
        {
            return preferredIndex
        }

        let exactMatches = queue.indices.filter { exactlyMatches(queue[$0], song) }
        if preferFollowingMatch,
           let currentIndex,
           let following = exactMatches.first(where: { $0 > currentIndex })
        {
            return following
        }
        if let exact = exactMatches.first {
            return exact
        }

        let idMatches = queue.indices.filter { queue[$0].id == song.id }
        if preferFollowingMatch,
           let currentIndex,
           let following = idMatches.first(where: { $0 > currentIndex })
        {
            return following
        }
        return idMatches.first
    }

    static func nextSelection(
        currentSong: Song,
        currentIndex: Int?,
        queue: [Song],
        wrapsAtEnd: Bool
    ) -> Selection? {
        guard !queue.isEmpty,
              let resolvedCurrentIndex = resolvedIndex(
                  for: currentSong,
                  in: queue,
                  preferredIndex: currentIndex
              )
        else { return nil }

        let nextIndex: Int
        if queue.indices.contains(resolvedCurrentIndex + 1) {
            nextIndex = resolvedCurrentIndex + 1
        } else if wrapsAtEnd {
            nextIndex = queue.startIndex
        } else {
            return nil
        }
        return Selection(index: nextIndex, song: queue[nextIndex])
    }

    static func previousSelection(
        currentSong: Song,
        currentIndex: Int?,
        queue: [Song]
    ) -> Selection? {
        guard !queue.isEmpty,
              let resolvedCurrentIndex = resolvedIndex(
                  for: currentSong,
                  in: queue,
                  preferredIndex: currentIndex
              ),
              queue.indices.contains(resolvedCurrentIndex - 1)
        else { return nil }

        let previousIndex = resolvedCurrentIndex - 1
        return Selection(index: previousIndex, song: queue[previousIndex])
    }

    static func hasSameIDOrder(_ lhs: [Song], _ rhs: [Song]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
        }
    }

    static func exactlyMatches(_ lhs: Song, _ rhs: Song) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.duration == rhs.duration
            && lhs.absolutePath == rhs.absolutePath
            && lhs.cloudflareID == rhs.cloudflareID
            && lhs.coverArt?.absolutePath == rhs.coverArt?.absolutePath
            && lhs.coverArt?.cloudflareId == rhs.coverArt?.cloudflareId
            && lhs.originalArtists == rhs.originalArtists
            && lhs.coverArtists == rhs.coverArtists
            && lhs.userUploaded == rhs.userUploaded
            && lhs.oss == rhs.oss
    }
}
