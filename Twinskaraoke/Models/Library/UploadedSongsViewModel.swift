import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class UploadedSongsViewModel {
    private(set) var songs: [Song] = [] {
        didSet { songsGeneration &+= 1 }
    }
    private(set) var displayedSongs: [Song] = []
    private(set) var isLoading = false
    private(set) var requiresSignIn = false
    private(set) var loadFailed = false
    var sort: LibrarySongSort = .recentlyAdded {
        didSet { rebuildDisplayedSongs() }
    }
    var searchText = "" {
        didSet { scheduleDisplayedSongsRebuild() }
    }

    private var hasLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private var requestGeneration = 0
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastRebuiltSearchText = ""
    private var songsGeneration: UInt64 = 0
    private var sortCache: (sort: LibrarySongSort, generation: UInt64, songs: [Song])?

    /// Replaces `$searchText.debounce(200ms).removeDuplicates()`. Filtering a
    /// large library runs localized comparisons per song, so keystrokes must
    /// still coalesce.
    private func scheduleDisplayedSongsRebuild() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            guard searchText != lastRebuiltSearchText else { return }
            lastRebuiltSearchText = searchText
            rebuildDisplayedSongs()
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        startLoad()
    }

    func refresh() async {
        startLoad()
        let task = loadTask
        await task?.value
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = nil
        requestGeneration &+= 1
        let generation = requestGeneration
        loadFailed = false

        guard CredentialStore.token != nil else {
            requiresSignIn = true
            isLoading = false
            hasLoaded = true
            songs = []
            rebuildDisplayedSongs()
            return
        }

        requiresSignIn = false
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                let loadedSongs = try await KaraokeAPIClient.uploadedSongs()
                let uniqueSongs = Self.removingDuplicateSongs(loadedSongs)
                try Task.checkCancellation()
                guard let self, generation == requestGeneration else { return }

                songs = uniqueSongs
                hasLoaded = true
                isLoading = false
                rebuildDisplayedSongs()

                let songsWithDurations = await UploadedSongDurationResolver.shared
                    .fillingMissingDurations(in: uniqueSongs)
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }

                songs = songsWithDurations
                loadTask = nil
                rebuildDisplayedSongs()
            } catch {
                guard !Self.isCancellationError(error) else { return }
                guard let self, generation == requestGeneration else { return }
                DebugLogger.log(
                    "Uploaded songs fetch failed: \(error.localizedDescription)",
                    category: .network
                )
                hasLoaded = true
                isLoading = false
                loadFailed = true
                loadTask = nil
            }
        }
    }

    // Sorting is the expensive half of a rebuild; cache it per (sort, songs)
    // so search keystrokes only pay for the filter pass.
    private var sortedSongs: [Song] {
        if let sortCache,
           sortCache.sort == sort,
           sortCache.generation == songsGeneration
        {
            return sortCache.songs
        }
        let sorted: [Song] = switch sort {
        case .recentlyAdded:
            songs
        case .title:
            songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            songs.sorted {
                $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending
            }
        case .duration:
            songs.sorted { $0.duration < $1.duration }
        }
        sortCache = (sort, songsGeneration, sorted)
        return sorted
    }

    private func rebuildDisplayedSongs() {
        let sorted = sortedSongs

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedSongs = sorted
            return
        }
        displayedSongs = sorted.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.displayArtist.localizedCaseInsensitiveContains(query)
                || song.displayTitle.localizedCaseInsensitiveContains(query)
        }
    }

    nonisolated static func removingDuplicateSongs(_ songs: [Song]) -> [Song] {
        var seenIDs = Set<String>()
        return songs.filter { seenIDs.insert($0.id).inserted }
    }

    nonisolated static func isCancellationError(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    deinit {
        loadTask?.cancel()
    }
}

actor UploadedSongDurationResolver {
    static let shared = UploadedSongDurationResolver()

    private var resolvedDurations: [String: Int] = [:]
    @ObservationIgnored private var lookupTasks: [String: Task<Int?, Never>] = [:]

    func fillingMissingDurations(
        in songs: [Song],
        localAudioURLs: [String: URL] = [:]
    ) async -> [Song] {
        for song in songs where song.duration > 0 {
            resolvedDurations[song.id] = song.duration
        }

        let songsNeedingDuration = songs.filter {
            $0.duration <= 0
                && resolvedDurations[$0.id] == nil
                && Self.preferredAudioURL(
                    for: $0,
                    localAudioURLs: localAudioURLs
                ) != nil
        }
        let songIDs = Set(songs.map(\.id))
        var durationsForSongs = resolvedDurations.filter { songIDs.contains($0.key) }
        guard !songsNeedingDuration.isEmpty else {
            return Self.applyingResolvedDurations(durationsForSongs, to: songs)
        }

        let maximumConcurrentLookups = 4

        for batchStart in stride(
            from: 0,
            to: songsNeedingDuration.count,
            by: maximumConcurrentLookups
        ) {
            guard !Task.isCancelled else { return songs }
            let batchEnd = min(
                batchStart + maximumConcurrentLookups,
                songsNeedingDuration.count
            )
            let batch = songsNeedingDuration[batchStart..<batchEnd]

            await withTaskGroup(of: (String, Int?).self) { group in
                for song in batch {
                    group.addTask { [self] in
                        let sourceURL = Self.preferredAudioURL(
                            for: song,
                            localAudioURLs: localAudioURLs
                        )
                        return (song.id, await duration(for: song, sourceURL: sourceURL))
                    }
                }
                for await (songID, duration) in group {
                    if let duration {
                        durationsForSongs[songID] = duration
                    }
                }
            }
        }

        return Self.applyingResolvedDurations(durationsForSongs, to: songs)
    }

    nonisolated static func applyingResolvedDurations(
        _ durations: [String: Int],
        to songs: [Song]
    ) -> [Song] {
        songs.map { song in
            guard song.duration <= 0,
                  let duration = durations[song.id],
                  duration > 0 else {
                return song
            }
            return Song(
                id: song.id,
                title: song.title,
                duration: duration,
                absolutePath: song.absolutePath,
                cloudflareID: song.cloudflareID,
                coverArt: song.coverArt,
                originalArtists: song.originalArtists,
                coverArtists: song.coverArtists,
                userUploaded: song.userUploaded,
                oss: song.oss,
                // Carried through: this rebuild runs over playlist songs, and
                // losing `order` here silently reverted them to an unpositioned
                // state that reordering then had to guess at.
                order: song.order
            )
        }
    }

    nonisolated static func preferredAudioURL(
        for song: Song,
        localAudioURLs: [String: URL]
    ) -> URL? {
        localAudioURLs[song.id] ?? song.audioURL
    }

    private func duration(for song: Song, sourceURL: URL?) async -> Int? {
        if let resolvedDuration = resolvedDurations[song.id] {
            return resolvedDuration
        }
        if let lookupTask = lookupTasks[song.id] {
            return await lookupTask.value
        }

        let lookupTask = Task {
            await Self.loadDuration(from: sourceURL)
        }
        lookupTasks[song.id] = lookupTask
        let duration = await lookupTask.value
        lookupTasks[song.id] = nil
        if let duration {
            resolvedDurations[song.id] = duration
        }
        return duration
    }

    private nonisolated static func loadDuration(from audioURL: URL?) async -> Int? {
        guard !Task.isCancelled, let audioURL else { return nil }
        do {
            let duration = try await AVURLAsset(url: audioURL).load(.duration)
            try Task.checkCancellation()
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return nil }
            return max(1, Int(seconds.rounded()))
        } catch {
            return nil
        }
    }

}
