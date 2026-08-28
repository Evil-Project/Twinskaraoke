import Foundation

/// Pure queue state kept separate from audio-engine and UI concerns.
///
/// Keeping every mutation here makes shuffle restoration and Up Next editing
/// deterministic and independently testable. `AudioPlayerManager` remains the
/// observable facade used by views.
nonisolated struct PlaybackQueueState: Equatable, Sendable {
    enum Advance: Equatable, Sendable {
        case replayCurrent
        case play(Song)
        case autoplay
        case stop
    }

    private(set) var items: [Song] = []
    private(set) var originalItems: [Song] = []
    private(set) var isShuffled = false

    mutating func replaceContext(
        _ context: [Song],
        current: Song,
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) {
        guard !context.isEmpty else { return }
        if isShuffled {
            originalItems = context
            items = [current] + shuffling(context.filter { $0.id != current.id })
        } else {
            items = context
            originalItems = []
        }
    }

    mutating func clear() {
        items = []
        originalItems = []
        isShuffled = false
    }

    mutating func insertNext(_ song: Song, after current: Song) {
        items = Self.inserting(song, into: items, after: current)
        if !originalItems.isEmpty {
            originalItems = Self.inserting(song, into: originalItems, after: current)
        }
    }

    func advance(
        after current: Song?,
        repeatMode: RepeatMode,
        autoplayEnabled: Bool
    ) -> Advance {
        if repeatMode == .one, current != nil {
            return .replayCurrent
        }
        if let current,
           let index = items.firstIndex(where: { $0.id == current.id }),
           items.indices.contains(index + 1)
        {
            return .play(items[index + 1])
        }
        if repeatMode == .all, let first = items.first {
            return .play(first)
        }
        return autoplayEnabled ? .autoplay : .stop
    }

    func previous(before current: Song?) -> Song? {
        guard let current,
              let index = items.firstIndex(where: { $0.id == current.id }),
              items.indices.contains(index - 1)
        else { return nil }
        return items[index - 1]
    }

    mutating func toggleShuffle(
        current: Song?,
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) {
        isShuffled.toggle()
        if isShuffled {
            originalItems = items
            guard let current else { return }
            items = [current] + shuffling(items.filter { $0.id != current.id })
        } else if !originalItems.isEmpty {
            items = originalItems
            originalItems = []
        }
    }

    mutating func beginInOrder(context: [Song]) {
        isShuffled = false
        originalItems = []
        items = context
    }

    mutating func beginShuffled(
        songs: [Song],
        selecting: ([Song]) -> Song? = { $0.randomElement() },
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) -> Song? {
        guard let selected = selecting(songs) else { return nil }
        isShuffled = true
        originalItems = songs
        items = [selected] + shuffling(songs.filter { $0.id != selected.id })
        return selected
    }

    mutating func moveUpNext(
        after current: Song?,
        from source: IndexSet,
        to destination: Int
    ) {
        guard let start = upNextStart(after: current) else { return }
        var upNext = Array(items[start...])
        guard source.allSatisfy(upNext.indices.contains), destination <= upNext.count else { return }
        let moving = source.map { upNext[$0] }
        for index in source.sorted(by: >) {
            upNext.remove(at: index)
        }
        let removedBeforeDestination = source.lazy.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), upNext.count)
        upNext.insert(contentsOf: moving, at: insertionIndex)
        items = Array(items[..<start]) + upNext
    }

    mutating func removeUpNext(after current: Song?, at offsets: IndexSet) {
        guard let start = upNextStart(after: current) else { return }
        var upNext = Array(items[start...])
        guard offsets.allSatisfy(upNext.indices.contains) else { return }
        for index in offsets.sorted(by: >) {
            upNext.remove(at: index)
        }
        items = Array(items[..<start]) + upNext
    }

    private func upNextStart(after current: Song?) -> Int? {
        guard let current,
              let index = items.firstIndex(where: { $0.id == current.id })
        else { return nil }
        let start = index + 1
        return items.indices.contains(start) ? start : nil
    }

    private static func inserting(_ song: Song, into source: [Song], after current: Song) -> [Song] {
        var updated = source
        updated.removeAll { $0.id == song.id && $0.id != current.id }
        if !updated.contains(where: { $0.id == current.id }) {
            updated.insert(current, at: 0)
        }
        guard song.id != current.id else { return updated }
        let currentIndex = updated.firstIndex(where: { $0.id == current.id }) ?? 0
        updated.insert(song, at: min(currentIndex + 1, updated.count))
        return updated
    }
}
