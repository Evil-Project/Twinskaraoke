import Foundation
import Observation

@MainActor
@Observable
final class BandleGameViewModel {
    private(set) var phase: BandleGamePhase = .idle
    private(set) var mode: BandleMode = .normal
    private(set) var challenge: BandleChallenge?
    private(set) var playStatus: BandlePlayStatus?
    private(set) var userData: BandleUserData?
    private(set) var result: BandleResult?
    private(set) var attempts: [BandleAttempt] = []
    private(set) var currentAttemptNumber = 1
    private(set) var visibleAttemptNumber = 1
    private(set) var currentClip: BandleAudioClip?
    private(set) var guessSongs: [BandleGuessSong] = []
    private(set) var selectedGuess: BandleGuessSong?
    private(set) var isPractice = false
    private(set) var excludeFromLeaderboard = false
    private(set) var isLoadingClip = false
    /// The answer as a full song, fetched once the game is over.
    private(set) var revealedSong: Song?
    private(set) var errorMessage: String?
    private(set) var isSignedIn = false
    var searchText = ""
    var guessQuery: String {
        get { searchText }
        set {
            if selectedGuess?.displayName != newValue {
                selectedGuess = nil
            }
            searchText = newValue
        }
    }

    @ObservationIgnored private let service: Service
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let readSignedIn: @MainActor () -> Bool
    @ObservationIgnored private var pendingRetry: BandleGameRetry?
    /// Identifies the latest clip request; an older response is dropped.
    @ObservationIgnored private var clipRequest = 0
    @ObservationIgnored private var revealRequest = 0

    init(
        service: Service = AppRuntime.isUITestMode ? .uiTestFixture : .live,
        defaults: UserDefaults = .standard,
        isSignedIn: @escaping @MainActor () -> Bool = { CredentialStore.isAuthenticated }
    ) {
        self.service = service
        self.defaults = defaults
        readSignedIn = isSignedIn
    }

    /// Per account, so one player's play-privately choice never applies to
    /// another account on the same device.
    private var exclusionKey: String {
        let account = playStatus?.userId ?? "guest"
        return "nk.bandle.excludeFromLeaderboard.\(account).\(mode.rawValue).\(challenge?.date ?? "unknown")"
    }

    var filteredSongs: [BandleGuessSong] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return guessSongs }
        return guessSongs.filter { song in
            [song.displayName, song.title, song.originalArtists, song.coverArtists]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var isChallengeInvalid: Bool {
        challenge?.isInvalid == true
    }

    /// What the screen's player should hold: the revealed song once the
    /// game is over, otherwise the current clip.
    var playbackURL: URL? {
        phase == .completed ? revealedSong?.audioURL : currentClip?.playableURL
    }

    var canSubmitGuess: Bool {
        phase == .playing && selectedGuess?.songId != nil && !isLoadingClip
    }

    func loadIfNeeded() async {
        switch phase {
        case .idle:
            await reload()
        case .playing where currentClip == nil && !isLoadingClip:
            // The clip load was cancelled when the screen went away.
            await loadClip(number: visibleAttemptNumber)
        default:
            return
        }
    }

    func reload() async {
        guard !phase.isBusy else { return }
        phase = .loading
        clearError()
        isSignedIn = readSignedIn()
        result = nil
        attempts = []
        hideRevealedSong()
        dropClipRequest()
        selectedGuess = nil
        searchText = ""
        isPractice = false
        excludeFromLeaderboard = false
        do {
            async let todayRequest = service.today(false, mode)
            async let statusRequest = service.playStatus(mode)
            async let dataRequest = service.userData(mode)
            async let songsRequest = service.songs(nil, mode)
            challenge = try await todayRequest
            playStatus = try await statusRequest
            excludeFromLeaderboard = defaults.bool(forKey: exclusionKey)
            userData = try await dataRequest
            guessSongs = try await songsRequest
            if challenge?.isInvalid == true {
                phase = .ready
                errorMessage = challenge?.invalidationMessage ?? String(localized: "Today's challenge is unavailable.")
            } else if playStatus?.hasPlayed == true {
                result = userData?.lastResult
                attempts = result?.attempts ?? []
                currentAttemptNumber = result?.attemptNumber ?? max(attempts.count, 1)
                visibleAttemptNumber = currentAttemptNumber
                phase = .completed
                await revealSong()
            } else if playStatus?.inProgress == true, let progress = playStatus?.progress {
                resume(progress)
                let lastAttempt = attempts.last
                if lastAttempt?.status == .correct || attempts.count >= 6 {
                    phase = .submitting
                    let guess = guessSongs.first { $0.songId == lastAttempt?.guessedSongId }
                    await finish(won: lastAttempt?.status == .correct, guess: guess)
                } else {
                    phase = .playing
                    await loadClip(number: currentAttemptNumber)
                }
            } else {
                currentAttemptNumber = 1
                visibleAttemptNumber = 1
                phase = .ready
            }
        } catch {
            // The screen went away mid-load; `loadIfNeeded()` starts over
            // when it appears again.
            guard !Task.isCancelled else {
                phase = .idle
                return
            }
            phase = .ready
            fail(String(localized: "Couldn't load Bandle. Check your connection and try again."), retry: .reload)
        }
    }

    /// Repeats whatever failed last: the clip, the guess, the practice round,
    /// or, for anything else, the whole load.
    func retry() async {
        let retry = pendingRetry ?? .reload
        switch retry {
        case .reload:
            await reload()
        case .practice:
            await startPractice()
        case let .clip(number):
            await loadClip(number: number)
        case let .attempt(guess, isSkip):
            guard phase == .playing else { return }
            await performAttempt(guess: guess, isSkip: isSkip)
        }
    }

    func selectMode(_ newMode: BandleMode) async {
        guard mode != newMode, !phase.isBusy else { return }
        mode = newMode
        phase = .idle
        await reload()
    }

    func start(excludeFromLeaderboard: Bool = false) async {
        guard phase == .ready, challenge?.isInvalid != true else { return }
        phase = .starting
        clearError()
        do {
            _ = try await service.start(excludeFromLeaderboard, mode)
            attempts = []
            currentAttemptNumber = 1
            visibleAttemptNumber = 1
            isPractice = false
            hideRevealedSong()
            self.excludeFromLeaderboard = excludeFromLeaderboard
            defaults.set(excludeFromLeaderboard, forKey: exclusionKey)
            phase = .playing
            await loadClip(number: 1)
        } catch KaraokeAPIClient.APIError.httpStatus(409) {
            // Today's game was already finished, for example on another
            // device. Reloading shows its result.
            phase = .ready
            await reload()
        } catch {
            phase = .ready
            guard !Task.isCancelled else { return }
            fail(String(localized: "Couldn't start today's challenge. Please try again."), retry: .reload)
        }
    }

    func startPractice() async {
        guard !phase.isBusy else { return }
        let previousPhase = phase
        phase = .starting
        clearError()
        do {
            let practiceChallenge = try await service.today(true, mode)
            let songs = try await service.songs(practiceChallenge.replaySongId, mode)
            challenge = practiceChallenge
            guessSongs = songs
            attempts = []
            result = nil
            selectedGuess = nil
            searchText = ""
            currentAttemptNumber = 1
            visibleAttemptNumber = 1
            isPractice = true
            hideRevealedSong()
            excludeFromLeaderboard = true
            phase = .playing
            await loadClip(number: 1)
        } catch {
            // Nothing was replaced yet, so the screen goes back to what it
            // showed, such as today's result.
            phase = previousPhase
            guard !Task.isCancelled else { return }
            fail(String(localized: "Couldn't start Bandle practice. Please try again."), retry: .practice)
        }
    }

    func selectGuess(_ song: BandleGuessSong) {
        selectedGuess = song
        searchText = song.displayName
    }

    func clearGuess() {
        selectedGuess = nil
        searchText = ""
    }

    func submitSelectedGuess() async {
        guard canSubmitGuess, let selectedGuess else { return }
        await performAttempt(guess: selectedGuess, isSkip: false)
    }

    func skip() async {
        guard phase == .playing else { return }
        await performAttempt(guess: nil, isSkip: true)
    }

    func loadClip(number: Int) async {
        // Once the game is over the full song replaces the clips.
        guard phase != .completed, number >= 1, number <= currentAttemptNumber else { return }
        clipRequest += 1
        let request = clipRequest
        isLoadingClip = true
        visibleAttemptNumber = number
        currentClip = nil
        clearError()
        do {
            let clip: BandleAudioClip?
            if isPractice {
                clip = challenge?.audioClips?.first { $0.attemptNumber == number }
            } else {
                clip = try await service.audio(number, mode)
            }
            // A newer request (another clip, a skip, a new round) replaced
            // this one while it loaded.
            guard request == clipRequest else { return }
            isLoadingClip = false
            currentClip = clip
            if clip == nil {
                fail(String(localized: "This Bandle clip isn't available."), retry: .practice)
            }
        } catch {
            guard request == clipRequest else { return }
            isLoadingClip = false
            guard !Task.isCancelled else { return }
            fail(String(localized: "Couldn't load this Bandle clip. Tap it to try again."), retry: .clip(number))
        }
    }

    /// The clip player couldn't play the loaded clip, for example because its
    /// download failed. Retry loads the clip again. For the revealed song
    /// there is no clip to reload; its Play button starts over instead.
    func clipPlaybackFailed() {
        guard phase != .completed else { return }
        fail(
            String(localized: "Couldn't load this Bandle clip. Tap it to try again."),
            retry: .clip(visibleAttemptNumber)
        )
    }

    private func revealSong() async {
        guard let songId = isPractice ? challenge?.replaySongId : result?.songId else { return }
        revealRequest += 1
        let request = revealRequest
        do {
            let song = try await service.song(songId)
            guard request == revealRequest, phase == .completed else { return }
            revealedSong = song
        } catch {
            // The result already names the song; the card shows that instead.
            DebugLogger.log("Bandle song reveal failed: \(error)", category: .network)
        }
    }

    private func hideRevealedSong() {
        revealRequest += 1
        revealedSong = nil
    }

    private func dropClipRequest() {
        clipRequest += 1
        isLoadingClip = false
        currentClip = nil
    }

    private func performAttempt(guess: BandleGuessSong?, isSkip: Bool) async {
        phase = .submitting
        clearError()
        do {
            let attempt: BandleAttempt
            if isPractice {
                let status: BandleAttemptStatus = isSkip ? .skipped : (guess?.songId == challenge?.replaySongId ? .correct : .incorrect)
                attempt = BandleAttempt(
                    clipLength: currentClip?.clipLength ?? 0,
                    attemptNumber: currentAttemptNumber,
                    status: status,
                    guessedSongId: guess?.songId,
                    guessedSongTitle: guess?.title
                )
            } else {
                attempt = try await service.attempt(
                    BandleAttemptInput(attemptNumber: currentAttemptNumber, guessedSongId: guess?.songId, isSkip: isSkip, mode: mode)
                )
            }
            attempts.append(attempt)
            selectedGuess = nil
            searchText = ""
            let didWin = attempt.status == .correct
            let isLastAttempt = currentAttemptNumber >= 6
            if didWin || isLastAttempt {
                await finish(won: didWin, guess: guess)
            } else {
                currentAttemptNumber += 1
                visibleAttemptNumber = currentAttemptNumber
                phase = .playing
                await loadClip(number: currentAttemptNumber)
            }
        } catch KaraokeAPIClient.APIError.httpStatus(409) {
            // The server already has this attempt, for example because the
            // response to an earlier try was lost. Resume from its progress.
            phase = .playing
            await reload()
        } catch {
            phase = .playing
            guard !Task.isCancelled else { return }
            fail(
                String(localized: "Couldn't submit that Bandle attempt. Please try again."),
                retry: .attempt(guess: guess, isSkip: isSkip)
            )
        }
    }

    private func finish(won: Bool, guess: BandleGuessSong?) async {
        if isPractice {
            let answer = guessSongs.first { $0.songId == challenge?.replaySongId }
            result = BandleResult(
                completedAt: Date.now.ISO8601Format(),
                won: won,
                attempts: attempts,
                attemptNumber: currentAttemptNumber,
                songId: answer?.songId,
                songTitle: answer?.title,
                artist: answer?.coverArtists ?? answer?.originalArtists,
                challengeDate: challenge?.date
            )
            phase = .completed
            await revealSong()
            return
        }
        do {
            result = try await service.complete(
                BandleCompletionInput(
                    won: won,
                    attemptNumber: currentAttemptNumber,
                    songId: won ? guess?.songId : nil,
                    songTitle: won ? guess?.title : nil,
                    artist: won ? (guess?.coverArtists ?? guess?.originalArtists) : nil,
                    attempts: attempts,
                    excludeFromLeaderboard: excludeFromLeaderboard,
                    mode: mode
                )
            )
            defaults.removeObject(forKey: exclusionKey)
            phase = .completed
            await revealSong()
        } catch {
            // Cancelled before the result was confirmed: the next load
            // resumes the finished attempts and completes again.
            guard !Task.isCancelled else {
                phase = .idle
                return
            }
            phase = .completed
            fail(
                String(localized: "Your attempt was saved, but Bandle couldn't confirm the result. Reload to finish."),
                retry: .reload
            )
        }
    }

    private func fail(_ message: String, retry: BandleGameRetry) {
        errorMessage = message
        pendingRetry = retry
    }

    private func clearError() {
        errorMessage = nil
        pendingRetry = nil
    }

    /// The saved attempts decide where the game continues. The server's
    /// `currentAttemptNumber` is undocumented and was 0 for a session with no
    /// attempts, so it is used only when no attempts come back.
    private func resume(_ progress: BandleProgress) {
        attempts = progress.attempts ?? []
        let attempt: Int
        if let last = attempts.last {
            let lastNumber = last.attemptNumber ?? attempts.count
            let isFinished = last.status == .correct || attempts.count >= 6
            attempt = isFinished ? lastNumber : lastNumber + 1
        } else {
            attempt = progress.currentAttemptNumber ?? 1
        }
        DebugLogger.log(
            "Bandle resume: server attempt \(progress.currentAttemptNumber.map(String.init) ?? "nil"), \(attempts.count) saved, continuing at \(attempt)",
            category: .network
        )
        currentAttemptNumber = min(max(attempt, 1), 6)
        visibleAttemptNumber = currentAttemptNumber
    }
}
