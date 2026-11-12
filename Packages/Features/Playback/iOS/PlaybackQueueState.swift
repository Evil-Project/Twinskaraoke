import Foundation

/// Pure queue state shared by the player, Up Next and session restoration.
nonisolated struct PlaybackQueueState: Equatable, Sendable, Codable {
    struct Entry: Equatable, Identifiable, Sendable {
        let id: UUID
        let song: Song

        init(id: UUID = UUID(), song: Song) {
            self.id = id
            self.song = song
        }
    }

    enum Advance: Equatable, Sendable {
        case replayCurrent(Song)
        case play(Song)
        case autoplay
        case stop
    }

    private var entries: [Entry] = []
    private var originalEntries: [Entry] = []
    private(set) var currentEntryID: UUID?
    private(set) var isShuffled = false
    /// Older sessions infer collection repeat from the saved queue.
    private(set) var repeatsCollection: Bool?

    var items: [Song] { entries.map(\.song) }
    var originalItems: [Song] { originalEntries.map(\.song) }
    var hasRepeatCollection: Bool { repeatsCollection ?? (entries.count > 1) }

    mutating func selectSingleSong() { repeatsCollection = false }

    mutating func selectEntry(_ id: UUID?) {
        currentEntryID = id.flatMap { containsEntry($0) ? $0 : nil }
    }

    func containsEntry(_ id: UUID) -> Bool { entries.contains { $0.id == id } }

    func entry(for song: Song) -> Entry? { entries.first { $0.song.id == song.id } }

    private func currentIndex(for song: Song?) -> Int? {
        guard let song else { return nil }
        return entries.firstIndex { $0.id == currentEntryID && $0.song.id == song.id }
            ?? entries.firstIndex { $0.song.id == song.id }
    }

    func upNext(after current: Song?) -> ArraySlice<Entry> {
        guard let index = currentIndex(for: current) else { return [] }
        return entries.suffix(from: index + 1)
    }

    mutating func beginAutoplay(context: [Song], current: Song) {
        repeatsCollection = true
        currentEntryID = nil
        replaceContext(context, current: current)
    }

    mutating func replaceContext(
        _ context: [Song],
        current: Song,
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) {
        if context.isEmpty {
            currentEntryID = currentIndex(for: current).map { entries[$0].id }
            return
        }
        if !isShuffled, items == context {
            currentEntryID = currentIndex(for: current).map { entries[$0].id }
            return
        }
        entries = context.map { Entry(song: $0) }
        currentEntryID = entry(for: current)?.id
        if isShuffled {
            originalEntries = entries
            let selected = entry(for: current) ?? Entry(song: current)
            entries = [selected] + Self.reorder(entries.filter { $0.id != selected.id }, as: shuffling)
            currentEntryID = selected.id
        } else {
            originalEntries = []
        }
    }

    mutating func mirror(_ songs: [Song], shuffled: Bool) {
        if items != songs {
            entries = songs.map { Entry(song: $0) }
            currentEntryID = nil
        }
        originalEntries = []
        isShuffled = shuffled
        repeatsCollection = songs.count > 1
    }

    mutating func clear() {
        entries = []
        originalEntries = []
        currentEntryID = nil
        repeatsCollection = nil
    }

    mutating func insertNext(_ song: Song, after current: Song) {
        insert(song, after: current, atEnd: false)
    }

    /// Explicit Play Next/Last move a waiting copy instead of adding a new duplicate.
    mutating func insertLast(_ song: Song, after current: Song) {
        insert(song, after: current, atEnd: true)
    }

    private mutating func insert(_ song: Song, after current: Song, atEnd: Bool) {
        let currentEntry = currentIndex(for: current).map { entries[$0] } ?? Entry(song: current)
        let queued = upNext(after: current).first { $0.song.id == song.id }
            ?? entry(for: song) ?? Entry(song: song)
        func updated(_ source: [Entry]) -> [Entry] {
            var result = source
            if !result.contains(where: { $0.id == currentEntry.id }) { result.insert(currentEntry, at: 0) }
            guard song.id != current.id else { return result }
            result.removeAll { $0.id == queued.id }
            let position = result.firstIndex { $0.id == currentEntry.id } ?? 0
            result.insert(queued, at: atEnd ? result.count : position + 1)
            return result
        }
        entries = updated(entries)
        if !originalEntries.isEmpty { originalEntries = updated(originalEntries) }
        currentEntryID = currentEntry.id
    }

    func nextEntry(after current: Song?, repeatMode: RepeatMode) -> Entry? {
        guard repeatMode != .one, repeatMode != .all || hasRepeatCollection,
              let index = currentIndex(for: current)
        else { return nil }
        if entries.indices.contains(index + 1) { return entries[index + 1] }
        return repeatMode == .all && entries.count > 1 ? entries.first : nil
    }

    func advance(after current: Song?, repeatMode: RepeatMode, autoplayEnabled: Bool) -> Advance {
        if let next = nextEntry(after: current, repeatMode: repeatMode) { return .play(next.song) }
        if let current, repeatMode != .off { return .replayCurrent(current) }
        return autoplayEnabled ? .autoplay : .stop
    }

    func crossfadeEntry(after current: Song?, repeatMode: RepeatMode) -> Entry? {
        guard let next = nextEntry(after: current, repeatMode: repeatMode),
              next.song.id != current?.id
        else { return nil }
        return next
    }

    func crossfadeTarget(after current: Song?, repeatMode: RepeatMode) -> Song? {
        crossfadeEntry(after: current, repeatMode: repeatMode)?.song
    }

    func skip(after current: Song?, autoplayEnabled: Bool) -> Advance {
        advance(after: current, repeatMode: .off, autoplayEnabled: autoplayEnabled)
    }

    static let previousRestartThreshold: TimeInterval = 3

    func previousEntry(before current: Song?, elapsed: TimeInterval = 0) -> Entry? {
        guard elapsed <= Self.previousRestartThreshold, let index = currentIndex(for: current), index > 0
        else { return nil }
        return entries[index - 1]
    }

    func previous(before current: Song?, elapsed: TimeInterval = 0) -> Song? {
        previousEntry(before: current, elapsed: elapsed)?.song
    }

    mutating func toggleShuffle(
        current: Song?,
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) {
        isShuffled.toggle()
        if isShuffled {
            originalEntries = entries
            guard let current else { return }
            let selected = currentIndex(for: current).map { entries[$0] } ?? Entry(song: current)
            entries = [selected] + Self.reorder(entries.filter { $0.id != selected.id }, as: shuffling)
            currentEntryID = selected.id
        } else if !originalEntries.isEmpty {
            entries = originalEntries
            originalEntries = []
        }
    }

    mutating func beginInOrder(context: [Song]) {
        repeatsCollection = true
        isShuffled = false
        originalEntries = []
        entries = context.map { Entry(song: $0) }
        currentEntryID = nil
    }

    mutating func beginShuffled(
        songs: [Song],
        selecting: ([Song]) -> Song? = { $0.randomElement() },
        shuffling: ([Song]) -> [Song] = { $0.shuffled() }
    ) -> Song? {
        guard let selected = selecting(songs) else { return nil }
        repeatsCollection = true
        isShuffled = true
        originalEntries = songs.map { Entry(song: $0) }
        let entry = originalEntries.first { $0.song.id == selected.id } ?? Entry(song: selected)
        entries = [entry] + Self.reorder(originalEntries.filter { $0.id != entry.id }, as: shuffling)
        currentEntryID = entry.id
        return selected
    }

    /// The shuffle callback works with songs. Match duplicate occurrences in source order.
    private static func reorder(_ source: [Entry], as shuffle: ([Song]) -> [Song]) -> [Entry] {
        let groups = Dictionary(grouping: source, by: { $0.song.id })
        var offsets: [String: Int] = [:]
        return shuffle(source.map(\.song)).compactMap { song in
            let index = offsets[song.id, default: 0]
            offsets[song.id] = index + 1
            guard let group = groups[song.id], group.indices.contains(index) else { return nil }
            return group[index]
        }
    }

    mutating func moveUpNext(after current: Song?, from source: IndexSet, to destination: Int) {
        guard let index = currentIndex(for: current) else { return }
        let start = index + 1
        var upNext = Array(entries.suffix(from: start))
        guard source.allSatisfy(upNext.indices.contains), (0...upNext.count).contains(destination) else { return }
        let moving = source.map { upNext[$0] }
        for index in source.reversed() { upNext.remove(at: index) }
        let insertionIndex = destination - source.lazy.filter { $0 < destination }.count
        upNext.insert(contentsOf: moving, at: insertionIndex)
        entries.replaceSubrange(start..., with: upNext)
    }

    @discardableResult
    mutating func removeUpNext(after current: Song?, at offsets: IndexSet) -> Set<UUID> {
        guard let index = currentIndex(for: current) else { return [] }
        let start = index + 1
        guard offsets.allSatisfy({ entries.indices.contains(start + $0) }) else { return [] }
        let removed = Set(offsets.map { entries[start + $0].id })
        for offset in offsets.reversed() { entries.remove(at: start + offset) }
        originalEntries.removeAll { removed.contains($0.id) }
        return removed
    }

    private enum CodingKeys: String, CodingKey {
        case items, originalItems, isShuffled, repeatsCollection, entryIDs, originalEntryIDs, currentEntryID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let songs = try values.decode([Song].self, forKey: .items)
        let originalSongs = try values.decode([Song].self, forKey: .originalItems)
        let entryIDs = try values.decodeIfPresent([UUID].self, forKey: .entryIDs)
        let originalIDs = try values.decodeIfPresent([UUID].self, forKey: .originalEntryIDs)
        if let entryIDs, entryIDs.count == songs.count {
            entries = zip(entryIDs, songs).map { Entry(id: $0, song: $1) }
        } else {
            entries = songs.map { Entry(song: $0) }
        }
        if let originalIDs, originalIDs.count == originalSongs.count {
            originalEntries = zip(originalIDs, originalSongs).map { Entry(id: $0, song: $1) }
        } else if !originalSongs.isEmpty {
            var activeBySong = Dictionary(grouping: entries.reversed(), by: { $0.song.id })
            originalEntries = originalSongs.map { song in
                Entry(id: activeBySong[song.id]?.popLast()?.id ?? UUID(), song: song)
            }
        }
        currentEntryID = try values.decodeIfPresent(UUID.self, forKey: .currentEntryID)
        isShuffled = try values.decode(Bool.self, forKey: .isShuffled)
        repeatsCollection = try values.decodeIfPresent(Bool.self, forKey: .repeatsCollection)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(items, forKey: .items)
        try values.encode(originalItems, forKey: .originalItems)
        try values.encode(isShuffled, forKey: .isShuffled)
        try values.encodeIfPresent(repeatsCollection, forKey: .repeatsCollection)
        try values.encode(entries.map(\.id), forKey: .entryIDs)
        try values.encode(originalEntries.map(\.id), forKey: .originalEntryIDs)
        try values.encodeIfPresent(currentEntryID, forKey: .currentEntryID)
    }
}

nonisolated struct PlaybackSessionSnapshot: Codable {
    var version = 1
    let song: Song
    let queue: PlaybackQueueState
    let position: TimeInterval
    let repeatMode: RepeatMode
    let wasPlaying: Bool

    var resumePosition: TimeInterval {
        guard position.isFinite else { return 0 }
        return min(max(0, position), max(0, Double(song.duration)))
    }
}

nonisolated enum PlaybackSessionStore {
    private static let io = DispatchQueue(label: "PlaybackSessionStore", qos: .utility)
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.arguments.contains("-UITestPlaybackSession")
                ? "playback-session-uitest.json" : "playback-session.json")
    }

    static func load() async -> PlaybackSessionSnapshot? {
        await withCheckedContinuation { continuation in
            io.async {
                do {
                    if ProcessInfo.processInfo.arguments.contains("-UITestResetPlaybackSession") {
                        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                        continuation.resume(returning: nil)
                        return
                    }
                    let snapshot = try JSONDecoder().decode(PlaybackSessionSnapshot.self, from: Data(contentsOf: url))
                    continuation.resume(returning: snapshot.version == 1 ? snapshot : nil)
                } catch {
                    DebugLogger.log("Playback session read: \(error)", category: .playback)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func save(_ snapshot: PlaybackSessionSnapshot) {
        io.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                DebugLogger.log("Playback session write: \(error)", category: .playback)
            }
        }
    }
}
