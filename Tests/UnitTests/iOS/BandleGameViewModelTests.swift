import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
private final class FakeBandleGameService {
    struct AttemptCall: Equatable {
        let number: Int
        let songId: String?
        let isSkip: Bool
    }

    var status = BandlePlayStatus(hasPlayed: false, inProgress: false)
    var startCalls = 0
    var practiceCalls = 0
    var audioCalls: [Int] = []
    var attemptCalls: [AttemptCall] = []
    var completeCalls = 0
    var completionAttempts = 0
    var completedExclusion: Bool?
    var shouldFailSongs = false
    /// The next clip comes back without an audio URL.
    var nextClipWithoutURL = false
    var shouldFailAttempt = false
    var shouldFailComplete = false
    var shouldFailAudio = false
    var shouldFailPractice = false
    /// The server accepts the next attempt but the response is lost; the
    /// resubmission gets the documented 409.
    var loseAttemptResponse = false
    /// Holds the next clip response until `releaseAudio()`.
    var holdNextAudio = false
    private(set) var heldAudio: CheckedContinuation<Void, Never>?
    /// Cancels the task loading the next clip, as leaving the screen does.
    var cancelNextAudio = false
    private(set) var songCalls: [String] = []
    /// The completion response leaves out the song id, as it may on a loss.
    var completeWithoutSongId = false
    var userData = UITestFixtures.bandleUserData
    var shouldFailSong = false
    private var acceptedAttempts: Set<Int> = []
    /// Thrown by `/start`; a 409 also marks today's game as played, as the server does.
    var startError: (any Error)?

    func releaseAudio() {
        heldAudio?.resume()
        heldAudio = nil
    }

    var service: BandleGameViewModel.Service {
        BandleGameViewModel.Service(
            today: { ephemeral, _ in
                try Task.checkCancellation()
                if ephemeral {
                    self.practiceCalls += 1
                    if self.shouldFailPractice { throw URLError(.notConnectedToInternet) }
                }
                return ephemeral ? UITestFixtures.bandlePracticeChallenge : UITestFixtures.bandleChallenge
            },
            start: { _, mode in
                self.startCalls += 1
                if let error = self.startError {
                    self.status = BandlePlayStatus(hasPlayed: true, inProgress: false)
                    throw error
                }
                return BandleSession(startedAt: "2026-11-15T12:00:00Z", mode: mode)
            },
            audio: { number, mode in
                self.audioCalls.append(number)
                if self.shouldFailAudio { throw URLError(.resourceUnavailable) }
                if self.cancelNextAudio {
                    self.cancelNextAudio = false
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw CancellationError()
                }
                if self.nextClipWithoutURL {
                    self.nextClipWithoutURL = false
                    return BandleAudioClip(attemptNumber: number, clipLength: number * 3, mode: mode)
                }
                if self.holdNextAudio {
                    self.holdNextAudio = false
                    await withCheckedContinuation { self.heldAudio = $0 }
                    // A marker, so a late response is recognisable.
                    return BandleAudioClip(attemptNumber: number, clipLength: 999, mode: mode)
                }
                return UITestFixtures.bandleClip(attempt: number, mode: mode)
            },
            songs: { _, _ in
                if self.shouldFailSongs { throw URLError(.timedOut) }
                return UITestFixtures.bandleGuessSongs
            },
            attempt: { input in
                if self.shouldFailAttempt { throw URLError(.networkConnectionLost) }
                if self.acceptedAttempts.contains(input.attemptNumber) {
                    throw KaraokeAPIClient.APIError.httpStatus(409)
                }
                if self.loseAttemptResponse {
                    self.loseAttemptResponse = false
                    self.acceptedAttempts.insert(input.attemptNumber)
                    let accepted = BandleAttempt(clipLength: 3, attemptNumber: input.attemptNumber, status: .skipped)
                    self.status = BandlePlayStatus(
                        hasPlayed: false,
                        inProgress: true,
                        progress: BandleProgress(currentAttemptNumber: input.attemptNumber + 1, attempts: [accepted])
                    )
                    throw URLError(.networkConnectionLost)
                }
                self.attemptCalls.append(
                    AttemptCall(number: input.attemptNumber, songId: input.guessedSongId, isSkip: input.isSkip)
                )
                let correct = !input.isSkip && input.guessedSongId == UITestFixtures.bandleAnswer.songId
                return BandleAttempt(
                    clipLength: input.attemptNumber * 3,
                    attemptNumber: input.attemptNumber,
                    status: correct ? .correct : (input.isSkip ? .skipped : .incorrect),
                    guessedSongId: input.guessedSongId,
                    guessedSongTitle: UITestFixtures.bandleGuessSongs.first { $0.songId == input.guessedSongId }?.title
                )
            },
            complete: { input in
                self.completionAttempts += 1
                if self.shouldFailComplete { throw URLError(.networkConnectionLost) }
                self.completeCalls += 1
                self.completedExclusion = input.excludeFromLeaderboard
                return BandleResult(
                    completedAt: "2026-11-15T12:05:00Z",
                    won: input.won,
                    attempts: input.attempts,
                    attemptNumber: input.attemptNumber,
                    songId: self.completeWithoutSongId ? nil : (input.songId ?? UITestFixtures.bandleAnswer.songId),
                    songTitle: input.songTitle ?? UITestFixtures.bandleAnswer.title,
                    artist: input.artist
                )
            },
            playStatus: { _ in self.status },
            userData: { _ in self.userData },
            song: { id in
                self.songCalls.append(id)
                if self.shouldFailSong { throw URLError(.notConnectedToInternet) }
                return try #require(UITestFixtures.coreSongs.first { $0.id == id })
            }
        )
    }
}

@MainActor
@Suite("Bandle game view model")
struct BandleGameViewModelTests {
    @Test("Start advances an incorrect guess and completes a correct one")
    func recordedWin() async throws {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start(excludeFromLeaderboard: true)
        #expect(model.phase == .playing)
        #expect(fake.audioCalls == [1])

        model.selectGuess(try #require(UITestFixtures.bandleGuessSongs.last))
        await model.submitSelectedGuess()
        #expect(model.currentAttemptNumber == 2)
        #expect(model.attempts.map(\.status) == [.incorrect])

        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()
        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(fake.startCalls == 1)
        #expect(fake.completeCalls == 1)
        #expect(fake.completedExclusion == true)
        #expect(fake.attemptCalls == [
            .init(number: 1, songId: "ui-song-cure-for-me", isSkip: false),
            .init(number: 2, songId: "ui-song-hero", isSkip: false),
        ])
    }

    @Test("Has-played restores the next clip and previous attempts")
    func resumesSession() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(
                currentAttemptNumber: 2,
                attempts: [BandleAttempt(clipLength: 3, attemptNumber: 1, status: .skipped)]
            )
        )
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.phase == .playing)
        #expect(model.attempts.count == 1)
        #expect(model.currentAttemptNumber == 2)
        #expect(fake.startCalls == 0)
        #expect(fake.audioCalls == [2])
    }

    @Test("A game started before any guess resumes at the first attempt")
    func resumesUnplayedSession() async {
        // Seen on a device: the server reported attempt 0 for a session
        // with no attempts yet, which crashed the clip range check.
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(currentAttemptNumber: 0, attempts: [])
        )
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.phase == .playing)
        #expect(model.currentAttemptNumber == 1)
        #expect(fake.audioCalls == [1])
    }

    @Test("Resuming continues after the last saved attempt, however the server counts")
    func resumesAfterLastAttempt() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(
                currentAttemptNumber: 1,
                attempts: [BandleAttempt(clipLength: 3, attemptNumber: 1, status: .skipped)]
            )
        )
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.phase == .playing)
        #expect(model.currentAttemptNumber == 2)
        #expect(fake.audioCalls == [2])
    }

    @Test("A terminal resumed attempt completes without another guess")
    func resumesTerminalAttempt() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(
                currentAttemptNumber: 1,
                attempts: [BandleAttempt(
                    clipLength: 3,
                    attemptNumber: 1,
                    status: .correct,
                    guessedSongId: UITestFixtures.bandleAnswer.songId
                )]
            )
        )
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(fake.completeCalls == 1)
        #expect(fake.attemptCalls.isEmpty)
    }

    @Test("Six skips complete a loss at the sixth attempt")
    func exhaustsAttempts() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()

        for _ in 1 ... 6 {
            await model.skip()
        }

        #expect(model.phase == .completed)
        #expect(model.result?.won == false)
        #expect(model.attempts.count == 6)
        #expect(fake.completeCalls == 1)
        #expect(fake.attemptCalls.map(\.number) == Array(1 ... 6))
    }

    @Test("Practice compares locally and never writes a recorded session")
    func practiceStaysLocal() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)

        await model.startPractice()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()

        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(model.excludeFromLeaderboard)
        #expect(fake.practiceCalls == 1)
        #expect(fake.startCalls == 0)
        #expect(fake.attemptCalls.isEmpty)
        #expect(fake.completeCalls == 0)
    }

    @Test("A rejected attempt leaves the same attempt ready to retry")
    func attemptFailureDoesNotAdvance() async {
        let fake = FakeBandleGameService()
        fake.shouldFailAttempt = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)

        await model.submitSelectedGuess()

        #expect(model.phase == .playing)
        #expect(model.currentAttemptNumber == 1)
        #expect(model.attempts.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(fake.completeCalls == 0)
    }

    @Test("A failed clip request does not leave the previous clip active")
    func failedClipClearsPreviousClip() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        #expect(model.currentClip?.attemptNumber == 1)
        fake.shouldFailAudio = true

        await model.skip()

        #expect(model.currentAttemptNumber == 2)
        #expect(model.currentClip == nil)
        #expect(model.errorMessage != nil)
    }

    @Test("Unranked play survives in-progress restoration")
    func restoresLeaderboardExclusion() async throws {
        let suiteName = "BandleGameViewModelTests.exclusion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fake = FakeBandleGameService()
        let firstModel = BandleGameViewModel(service: fake.service, defaults: defaults)
        await firstModel.loadIfNeeded()
        await firstModel.start(excludeFromLeaderboard: true)
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(
                currentAttemptNumber: 1,
                attempts: [BandleAttempt(
                    clipLength: 3,
                    attemptNumber: 1,
                    status: .correct,
                    guessedSongId: UITestFixtures.bandleAnswer.songId
                )]
            )
        )
        let restored = BandleGameViewModel(service: fake.service, defaults: defaults)

        await restored.loadIfNeeded()

        #expect(restored.phase == .completed)
        #expect(fake.completedExclusion == true)
        #expect(fake.attemptCalls.isEmpty)
    }

    @Test("Failed completion locks further attempts until status reload")
    func failedCompletionDoesNotDuplicateAttempt() async {
        let fake = FakeBandleGameService()
        fake.shouldFailComplete = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()

        await model.skip()

        #expect(model.phase == .completed)
        #expect(model.result == nil)
        #expect(model.errorMessage != nil)
        #expect(fake.attemptCalls.count == 1)
        #expect(fake.completeCalls == 0)
        #expect(fake.completionAttempts == 1)
    }

    @Test("Guess filtering searches server titles and artists")
    func filtersGuessSongs() async throws {
        let model = BandleGameViewModel(service: FakeBandleGameService().service)
        await model.loadIfNeeded()
        model.searchText = "aurora"
        #expect(model.filteredSongs.map(\.songId) == ["ui-song-cure-for-me"])
        model.selectGuess(try #require(model.filteredSongs.first))
        #expect(model.searchText == "Cure For Me - AURORA")
        model.clearGuess()
        #expect(model.filteredSongs.count == 2)
    }

    @Test("Starting a game the server says is finished shows today's result")
    func startConflictShowsResult() async {
        let fake = FakeBandleGameService()
        fake.startError = KaraokeAPIClient.APIError.httpStatus(409)
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()

        await model.start()

        #expect(model.phase == .completed)
        #expect(model.result?.songId == UITestFixtures.bandleUserData.lastResult?.songId)
        #expect(model.errorMessage == nil)
    }

    @Test("Retrying a failed clip reloads only that clip")
    func retryReloadsFailedClip() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        fake.shouldFailAudio = true
        await model.skip()
        #expect(model.currentClip == nil)
        fake.shouldFailAudio = false

        await model.retry()

        #expect(model.phase == .playing)
        #expect(model.currentClip?.attemptNumber == 2)
        #expect(model.attempts.count == 1)
        #expect(model.errorMessage == nil)
        #expect(fake.audioCalls == [1, 2, 2])
        #expect(fake.startCalls == 1)
    }

    @Test("Retrying a rejected guess submits the same guess again")
    func retryResubmitsGuess() async {
        let fake = FakeBandleGameService()
        fake.shouldFailAttempt = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()
        fake.shouldFailAttempt = false

        await model.retry()

        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(fake.attemptCalls == [.init(number: 1, songId: UITestFixtures.bandleAnswer.songId, isSkip: false)])
    }

    @Test("A practice round that fails to start returns to the finished game")
    func failedPracticeKeepsResult() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()
        #expect(model.phase == .completed)
        fake.shouldFailPractice = true

        await model.startPractice()

        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(!model.isPractice)
        #expect(model.errorMessage != nil)
    }

    @Test("Signed-in state is read when the game loads", arguments: [true, false])
    func readsSignedInState(signedIn: Bool) async {
        let model = BandleGameViewModel(service: FakeBandleGameService().service, isSignedIn: { signedIn })

        await model.loadIfNeeded()

        #expect(model.isSignedIn == signedIn)
    }

    @Test("Reopening a finished game shows its saved attempts")
    func completedGameRestoresAttempts() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(hasPlayed: true, inProgress: false)
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.phase == .completed)
        #expect(model.attempts.map(\.status) == [.incorrect, .correct])
        #expect(model.currentAttemptNumber == 2)
    }

    @Test("A load cancelled mid-request runs again the next time the screen appears")
    func cancelledLoadCanLoadAgain() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)

        let load = Task { await model.loadIfNeeded() }
        load.cancel()
        await load.value
        #expect(model.phase == .idle)

        await model.loadIfNeeded()
        #expect(model.phase == .ready)
    }

    @Test("Retrying an attempt the server already accepted resumes its progress")
    func acceptedAttemptConflictResumes() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        fake.loseAttemptResponse = true

        await model.skip()
        #expect(model.errorMessage != nil)
        await model.retry()

        #expect(model.phase == .playing)
        #expect(model.currentAttemptNumber == 2)
        #expect(model.attempts.map(\.attemptNumber) == [1])
        #expect(model.errorMessage == nil)
    }

    @Test("A play-privately choice belongs to the account that made it")
    func exclusionIsPerAccount() async throws {
        let suiteName = "BandleGameViewModelTests.accounts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(userId: "account-a", hasPlayed: false, inProgress: false)
        let first = BandleGameViewModel(service: fake.service, defaults: defaults)
        await first.loadIfNeeded()
        await first.start(excludeFromLeaderboard: true)

        fake.status = BandlePlayStatus(userId: "account-b", hasPlayed: false, inProgress: false)
        let second = BandleGameViewModel(service: fake.service, defaults: defaults)
        await second.loadIfNeeded()

        #expect(!second.excludeFromLeaderboard)
    }

    @Test("A clip from the previous round never replaces the new round's clip")
    func lateClipFromEarlierRoundIsDropped() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        fake.holdNextAudio = true
        let ranked = Task { await model.start() }
        while fake.heldAudio == nil {
            await Task.yield()
        }

        await model.startPractice()
        fake.releaseAudio()
        await ranked.value

        #expect(model.isPractice)
        #expect(model.currentClip == UITestFixtures.bandlePracticeChallenge.audioClips?.first)
        #expect(!model.isLoadingClip)
    }

    @Test("A resumed game whose clip load was cancelled loads it when the screen returns")
    func cancelledResumedClipReloads() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(currentAttemptNumber: 2, attempts: [BandleAttempt(clipLength: 3, attemptNumber: 1, status: .skipped)])
        )
        fake.cancelNextAudio = true
        let model = BandleGameViewModel(service: fake.service)
        await Task { await model.loadIfNeeded() }.value
        #expect(model.currentClip == nil)

        await model.loadIfNeeded()

        #expect(fake.audioCalls == [2, 2])
        #expect(model.currentClip?.attemptNumber == 2)
    }

    @Test("A clip that can't be played shows the clip error with a retry")
    func clipPlaybackFailureOffersRetry() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()

        model.clipPlaybackFailed()
        #expect(model.errorMessage != nil)
        await model.retry()

        #expect(fake.audioCalls == [1, 1])
        #expect(model.errorMessage == nil)
        #expect(model.currentClip != nil)
    }

    @Test("A won game reveals the full song and locks the clips")
    func winRevealsSong() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()

        #expect(model.revealedSong?.id == UITestFixtures.bandleAnswer.songId)
        #expect(model.playbackURL == model.revealedSong?.audioURL)

        await model.loadClip(number: 3)
        #expect(fake.audioCalls == [1])
    }

    @Test("A lost game reveals the song too")
    func lossRevealsSong() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        for _ in 1 ... 6 {
            await model.skip()
        }

        #expect(model.result?.won == false)
        #expect(model.revealedSong?.id == UITestFixtures.bandleAnswer.songId)
    }

    @Test("Reopening a finished game reveals its song")
    func reopenRevealsSong() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(hasPlayed: true, inProgress: false)
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(fake.songCalls == [UITestFixtures.bandleAnswer.songId])
        #expect(model.revealedSong != nil)
    }

    @Test("Practice reveals its replayed song, and a new round hides it again")
    func practiceRevealsSong() async {
        let fake = FakeBandleGameService()
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.startPractice()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()
        #expect(model.revealedSong?.id == UITestFixtures.bandlePracticeChallenge.replaySongId)

        await model.startPractice()

        #expect(model.revealedSong == nil)
        #expect(model.playbackURL == model.currentClip?.playableURL)
    }

    @Test("A song that can't be fetched keeps the result without an error")
    func failedRevealKeepsResult() async {
        let fake = FakeBandleGameService()
        fake.shouldFailSong = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()

        #expect(model.phase == .completed)
        #expect(model.result?.won == true)
        #expect(model.revealedSong == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("A lost game whose result has no song id finds the song by its title")
    func lossWithoutSongIdRevealsByTitle() async {
        let fake = FakeBandleGameService()
        fake.completeWithoutSongId = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        for _ in 1 ... 6 {
            await model.skip()
        }

        #expect(model.result?.songId == nil)
        #expect(fake.songCalls == [UITestFixtures.bandleAnswer.songId])
        #expect(model.revealedSong?.id == UITestFixtures.bandleAnswer.songId)
    }

    @Test("A won game whose result has no song id uses the correct guess")
    func winWithoutSongIdUsesCorrectGuess() async {
        let fake = FakeBandleGameService()
        fake.completeWithoutSongId = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        model.selectGuess(UITestFixtures.bandleAnswer)
        await model.submitSelectedGuess()

        #expect(model.revealedSong?.id == UITestFixtures.bandleAnswer.songId)
    }

    @Test("Reopening a game whose saved result has an empty song id still reveals the song")
    func reopenWithEmptySongIdRevealsByTitle() async {
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(hasPlayed: true, inProgress: false)
        fake.userData = BandleUserData(
            lastResult: BandleResult(
                completedAt: "2026-11-15T12:05:00Z",
                won: false,
                songId: "",
                songTitle: UITestFixtures.bandleAnswer.title,
                artist: UITestFixtures.bandleAnswer.coverArtists
            )
        )
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(fake.songCalls == [UITestFixtures.bandleAnswer.songId])
        #expect(model.revealedSong?.id == UITestFixtures.bandleAnswer.songId)
    }

    @Test("A resumed game whose leaderboard choice isn't known here leaves it to the server")
    func resumedGameOmitsUnknownExclusion() async {
        let suiteName = "BandleGameViewModelTests.unknownExclusion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fake = FakeBandleGameService()
        fake.status = BandlePlayStatus(
            hasPlayed: false,
            inProgress: true,
            progress: BandleProgress(attempts: [BandleAttempt(
                clipLength: 3,
                attemptNumber: 1,
                status: .correct,
                guessedSongId: UITestFixtures.bandleAnswer.songId
            )])
        )
        let model = BandleGameViewModel(service: fake.service, defaults: defaults)

        await model.loadIfNeeded()

        #expect(fake.completeCalls == 1)
        #expect(fake.completedExclusion == nil)
    }

    @Test("A load that fails part-way offers Retry, not a game to start")
    func failedLoadHidesStart() async {
        let fake = FakeBandleGameService()
        fake.shouldFailSongs = true
        let model = BandleGameViewModel(service: fake.service)

        await model.loadIfNeeded()
        #expect(!model.canStart)
        await model.start()
        #expect(fake.startCalls == 0)

        fake.shouldFailSongs = false
        await model.retry()
        #expect(model.canStart)
    }

    @Test("A clip without an audio URL is reported with a retry")
    func clipWithoutURLFails() async {
        let fake = FakeBandleGameService()
        fake.nextClipWithoutURL = true
        let model = BandleGameViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.start()
        #expect(model.errorMessage != nil)

        await model.retry()

        #expect(fake.audioCalls == [1, 1])
        #expect(model.currentClip?.playableURL != nil)
        #expect(model.errorMessage == nil)
    }
}
