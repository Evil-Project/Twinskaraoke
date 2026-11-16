import Foundation

extension BandleGameViewModel {
    struct Service {
        var today: @MainActor (Bool, BandleMode) async throws -> BandleChallenge
        var start: @MainActor (Bool, BandleMode) async throws -> BandleSession
        var audio: @MainActor (Int, BandleMode) async throws -> BandleAudioClip
        var songs: @MainActor (String?, BandleMode) async throws -> [BandleGuessSong]
        var attempt: @MainActor (BandleAttemptInput) async throws -> BandleAttempt
        var complete: @MainActor (BandleCompletionInput) async throws -> BandleResult
        var playStatus: @MainActor (BandleMode) async throws -> BandlePlayStatus
        var userData: @MainActor (BandleMode) async throws -> BandleUserData

        static var live: Service {
            Service(
                today: KaraokeAPIClient.bandleToday,
                start: KaraokeAPIClient.bandleStart,
                audio: KaraokeAPIClient.bandleAudio,
                songs: { replaySongId, mode in
                    try await KaraokeAPIClient.bandleGuessableSongs(replaySongId: replaySongId, mode: mode)
                },
                attempt: KaraokeAPIClient.bandleSubmitAttempt,
                complete: KaraokeAPIClient.bandleComplete,
                playStatus: KaraokeAPIClient.bandlePlayStatus,
                userData: KaraokeAPIClient.bandleUserData
            )
        }

        static var uiTestFixture: Service {
            Service(
                today: { ephemeral, _ in
                    ephemeral ? UITestFixtures.bandlePracticeChallenge : UITestFixtures.bandleChallenge
                },
                start: { _, mode in BandleSession(startedAt: "2026-11-15T12:00:00Z", mode: mode) },
                audio: { attempt, mode in UITestFixtures.bandleClip(attempt: attempt, mode: mode) },
                songs: { _, _ in UITestFixtures.bandleGuessSongs },
                attempt: { input in
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
                    BandleResult(
                        completedAt: "2026-11-15T12:05:00Z",
                        won: input.won,
                        attempts: input.attempts,
                        attemptNumber: input.attemptNumber,
                        songId: input.won ? input.songId : UITestFixtures.bandleAnswer.songId,
                        songTitle: input.won ? input.songTitle : UITestFixtures.bandleAnswer.title,
                        artist: input.won ? input.artist : UITestFixtures.bandleAnswer.coverArtists
                    )
                },
                playStatus: { _ in BandlePlayStatus(hasPlayed: false, inProgress: false) },
                userData: { _ in UITestFixtures.bandleUserData }
            )
        }
    }
}
