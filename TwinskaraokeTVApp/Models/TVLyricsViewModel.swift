import Foundation
import Observation
@MainActor
@Observable
final class TVLyricsViewModel {
    private(set) var lyrics: [LyricLine] = []
    private(set) var isLoading = false
    private(set) var didFail = false
    private(set) var hasNoLyrics = false
    private var servedSongID: String?
    private var requestedSongID: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    private var cache: [String: [LyricLine]] = [:]
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
            let parsed = raw
                .compactMap { line -> LyricLine? in
                    guard let time = TimeSpanParser.parse(line.time) else { return nil }
                    return LyricLine(time: time, text: line.text)
                }
                .sorted { $0.time < $1.time }

            finish(songID: songID, outcome: parsed.isEmpty ? .empty : .success(parsed))
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            finish(songID: songID, outcome: .failure)
        }
    }

    private enum Outcome {
        case success([LyricLine])
        case empty
        case failure
    }

    private func finish(songID: String, outcome: Outcome) {
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
