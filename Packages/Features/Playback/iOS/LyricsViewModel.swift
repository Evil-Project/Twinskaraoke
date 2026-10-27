import Foundation
import Observation

enum LyricsTranslationState: Equatable {
    case idle
    case translating
    case ready
    case unavailable
    case failed
}

@MainActor
@Observable
final class LyricsViewModel {
    private(set) var lyrics: [LyricLine] = []
    private(set) var isLoading = false
    private(set) var didFail = false
    private(set) var hasNoLyrics = false
    private(set) var translationState: LyricsTranslationState = .idle

    // Read by the player view to match the prefetched model against the
    // incoming song; under @Published it was untracked and could read stale.
    private(set) var loadedSongID: String?
    @ObservationIgnored private var inFlightSongID: String?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var translationTask: Task<Void, Never>?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetchData: @MainActor (URLRequest) async throws -> Data
    @ObservationIgnored private let translate: @MainActor (String, [LyricLine]) async throws -> [LyricLine]
    @ObservationIgnored private let translationConfigured: @MainActor () -> Bool

    @ObservationIgnored private let readToken: () throws -> String?

    init(
        readToken: @escaping () throws -> String? = CredentialStore.requestToken,
        fetchData: @escaping @MainActor (URLRequest) async throws -> Data = { try await KaraokeAPIClient.data(for: $0) },
        translate: @escaping @MainActor (String, [LyricLine]) async throws -> [LyricLine] = {
            try await LyricsTranslationService.shared.translate(songID: $0, lyrics: $1)
        },
        translationConfigured: @escaping @MainActor () -> Bool = { LyricsTranslationService.shared.isConfigured }
    ) {
        self.readToken = readToken
        self.fetchData = fetchData
        self.translate = translate
        self.translationConfigured = translationConfigured
    }

    deinit {
        currentTask?.cancel()
        translationTask?.cancel()
    }

    var hasTranslatedLyrics: Bool {
        lyrics.contains { ($0.translatedText?.isEmpty == false) && $0.translatedText != $0.text }
    }

    func adopt(songID: String, lyrics: [LyricLine], hasNoLyrics: Bool = false) {
        cancelInFlight()
        inFlightSongID = nil
        loadedSongID = songID
        self.lyrics = lyrics.sorted { $0.time < $1.time }
        isLoading = false
        didFail = false
        let resolvedHasNoLyrics = hasNoLyrics || lyrics.isEmpty
        self.hasNoLyrics = resolvedHasNoLyrics
        if resolvedHasNoLyrics {
            translationState = .idle
        } else {
            refreshTranslationState(for: lyrics)
        }
    }

    func fetch(songID: String) {
        if songID == loadedSongID, !lyrics.isEmpty { return }
        if songID == loadedSongID, hasNoLyrics { return }
        if songID == inFlightSongID, isLoading { return }

        cancelInFlight()
        inFlightSongID = songID

        if let cachedTranslated = LyricsCacheStore.load(songID: songID, variant: .translated) {
            loadedSongID = songID
            lyrics = cachedTranslated.sorted { $0.time < $1.time }
            isLoading = false
            didFail = false
            hasNoLyrics = false
            translationState = .ready
            return
        }

        if let cachedOriginal = LyricsCacheStore.load(songID: songID, variant: .original) {
            loadedSongID = songID
            lyrics = cachedOriginal.sorted { $0.time < $1.time }
            isLoading = false
            didFail = false
            hasNoLyrics = false
            refreshTranslationState(for: cachedOriginal)
            return
        }

        if loadedSongID != songID {
            lyrics = []
            loadedSongID = nil
            hasNoLyrics = false
            translationState = .idle
        }

        isLoading = true
        didFail = false
        guard var request = try? KaraokeAPIClient.request(
            pathSegments: ["api", "songs", songID, "lyrics"], readToken: readToken
        ) else {
            finish(songID: songID, result: .failure)
            return
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let generation = generation
        let fetchData = self.fetchData
        currentTask = Task { [weak self] in
            do {
                let data = try await fetchData(request)
                try Task.checkCancellation()
                let raw = try JSONDecoder().decode([RawLyricLine].self, from: data)
                let parsed = raw.compactMap { line -> LyricLine? in
                    guard let time = TimeSpanParser.parse(line.time) else { return nil }
                    return LyricLine(time: time, text: line.text)
                }.sorted { $0.time < $1.time }
                guard let self, self.generation == generation else { return }
                finish(songID: songID, result: parsed.isEmpty ? .empty : .success(parsed))
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if case KaraokeAPIClient.APIError.httpStatus(404) = error {
                    finish(songID: songID, result: .empty)
                } else {
                    finish(songID: songID, result: .failure)
                }
            }
        }
    }

    func retry() {
        guard let id = inFlightSongID ?? loadedSongID else { return }
        cancelInFlight()
        inFlightSongID = nil
        isLoading = false
        loadedSongID = nil
        didFail = false
        hasNoLyrics = false
        lyrics = []
        translationState = .idle
        fetch(songID: id)
    }

    func requestTranslation() {
        guard let songID = loadedSongID, !lyrics.isEmpty, !hasNoLyrics else { return }
        if hasTranslatedLyrics {
            translationState = .ready
            return
        }
        if let cached = LyricsCacheStore.load(songID: songID, variant: .translated) {
            if let merged = mergeTranslations(from: cached, into: lyrics) {
                lyrics = merged
                refreshTranslationState(for: merged)
                return
            }
        }
        guard translationConfigured() else {
            translationState = .unavailable
            return
        }

        translationTask?.cancel()
        translationState = .translating
        let sourceLyrics = lyrics
        let generation = generation
        let translate = self.translate
        translationTask = Task { [weak self] in
            do {
                let translated = try await translate(songID, sourceLyrics)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                lyrics = translated
                refreshTranslationState(for: translated)
                translationTask = nil
                LyricsCacheStore.save(translated, songID: songID, variant: .translated)
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                translationTask = nil
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    refreshTranslationState(for: lyrics)
                } else if case LyricsTranslationError.unavailable = error {
                    translationState = .unavailable
                } else {
                    translationState = .failed
                }
            }
        }
    }

    private enum FetchResult {
        case success([LyricLine])
        case empty
        case failure
    }

    private func finish(songID: String, result: FetchResult) {
        inFlightSongID = nil
        currentTask = nil
        isLoading = false
        switch result {
        case let .success(parsed):
            loadedSongID = songID
            lyrics = parsed
            didFail = false
            hasNoLyrics = false
            refreshTranslationState(for: parsed)
            LyricsCacheStore.save(parsed, songID: songID, variant: .original)
        case .empty:
            loadedSongID = songID
            lyrics = []
            didFail = false
            hasNoLyrics = true
            translationState = .idle
        case .failure:
            loadedSongID = songID
            lyrics = []
            didFail = true
            hasNoLyrics = false
            translationState = .idle
        }
    }

    private func refreshTranslationState(for lyrics: [LyricLine]) {
        let hasTranslations = lyrics.contains {
            ($0.translatedText?.isEmpty == false) && $0.translatedText != $0.text
        }
        if hasTranslations {
            translationState = .ready
        } else {
            translationState = translationConfigured() ? .idle : .unavailable
        }
    }

    private func mergeTranslations(from translated: [LyricLine], into original: [LyricLine]) -> [LyricLine]? {
        guard translated.count == original.count,
              zip(original, translated).allSatisfy({ $0.time == $1.time && $0.text == $1.text })
        else { return nil }
        return zip(original, translated).map { source, translatedLine in
            source.withTranslation(translatedLine.translatedText ?? translatedLine.text)
        }
    }

    private func cancelInFlight() {
        generation &+= 1
        currentTask?.cancel()
        currentTask = nil
        translationTask?.cancel()
        translationTask = nil
    }
}
