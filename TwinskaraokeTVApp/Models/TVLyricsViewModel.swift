import Combine
import Foundation

/// Loads timed lyrics for the tvOS player.
///
/// Deliberately slimmer than the iOS `LyricsViewModel`: it hits the same
/// `/api/songs/{id}/lyrics` endpoint and reuses the same `RawLyricLine` /
/// `TimeSpanParser` decoding, but drops the on-disk cache and the translation
/// pipeline. The Apple TV is always online — the same reason `AudioManager`
/// streams instead of downloading — so an in-memory cache keyed by song is
/// enough to make returning to a song in the same session instant.
@MainActor
final class TVLyricsViewModel: ObservableObject {
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false
    @Published private(set) var hasNoLyrics = false

    /// The song a load is currently satisfied for. Cleared on failure so that
    /// coming back to the player retries instead of showing a stale error.
    private var servedSongID: String?
    /// The last song asked for, kept through failures purely so `retry` knows
    /// what to re-request.
    private var requestedSongID: String?

    private var task: Task<Void, Never>?
    private var cache: [String: [LyricLine]] = [:]
    /// Songs the API answered 404 for, so switching back and forth doesn't
    /// re-ask for something the catalog has already said it lacks.
    private var knownEmpty: Set<String> = []

    func load(songID: String) {
        guard servedSongID != songID else { return }

        task?.cancel()
        requestedSongID = songID
        servedSongID = songID
        didFail = false

        if let cached = cache[songID] {
            lyrics = cached
            hasNoLyrics = false
            isLoading = false
            return
        }

        lyrics = []

        if knownEmpty.contains(songID) {
            hasNoLyrics = true
            isLoading = false
            return
        }

        hasNoLyrics = false
        isLoading = true
        task = Task { [weak self] in
            await self?.fetch(songID: songID)
        }
    }

    func retry() {
        guard let songID = requestedSongID else { return }
        servedSongID = nil
        knownEmpty.remove(songID)
        load(songID: songID)
    }

    func clear() {
        task?.cancel()
        task = nil
        servedSongID = nil
        requestedSongID = nil
        lyrics = []
        isLoading = false
        didFail = false
        hasNoLyrics = false
    }

    private func fetch(songID: String) async {
        do {
            var request = try KaraokeAPIClient.request(
                pathSegments: ["api", "songs", songID, "lyrics"]
            )
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse else {
                finish(songID: songID, outcome: .failure)
                return
            }
            if http.statusCode == 404 {
                finish(songID: songID, outcome: .empty)
                return
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                finish(songID: songID, outcome: .failure)
                return
            }
            guard let raw = try? JSONDecoder().decode([RawLyricLine].self, from: data) else {
                finish(songID: songID, outcome: .failure)
                return
            }

            // Lines the server can't give a usable timestamp for are dropped
            // rather than pinned to zero, which would make them all light up
            // together during the intro. Sorting guards the binary search in
            // `TVLyricsView` against an out-of-order payload.
            let parsed = raw
                .compactMap { line -> LyricLine? in
                    guard let time = TimeSpanParser.parse(line.time) else { return nil }
                    return LyricLine(time: time, text: line.text)
                }
                .sorted { $0.time < $1.time }

            finish(songID: songID, outcome: parsed.isEmpty ? .empty : .success(parsed))
        } catch is CancellationError {
            return
        } catch {
            finish(songID: songID, outcome: .failure)
        }
    }

    private enum Outcome {
        case success([LyricLine])
        case empty
        case failure
    }

    private func finish(songID: String, outcome: Outcome) {
        // A response that landed after the player moved on is discarded, so a
        // slow request for the previous song can't overwrite the current one.
        guard servedSongID == songID else { return }
        isLoading = false
        switch outcome {
        case let .success(parsed):
            cache[songID] = parsed
            lyrics = parsed
            didFail = false
            hasNoLyrics = false
        case .empty:
            knownEmpty.insert(songID)
            lyrics = []
            didFail = false
            hasNoLyrics = true
        case .failure:
            servedSongID = nil
            lyrics = []
            didFail = true
            hasNoLyrics = false
        }
    }
}
