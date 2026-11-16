import Foundation

nonisolated extension UITestFixtures {
    static let bandleAnswer = BandleGuessSong(
        songId: "ui-song-hero",
        title: "Hero",
        originalArtists: "Mili",
        coverArtists: "Neuro",
        formattedName: "Hero - Mili"
    )

    static let bandleGuessSongs = [
        bandleAnswer,
        BandleGuessSong(
            songId: "ui-song-cure-for-me",
            title: "Cure For Me",
            originalArtists: "AURORA",
            coverArtists: "Evil",
            formattedName: "Cure For Me - AURORA"
        ),
    ]

    static let bandleChallenge = BandleChallenge(
        id: "bandle-fixture",
        date: "2026-11-15T00:00:00Z",
        totalPlays: 42,
        totalWins: 35,
        averageAttempt: 2.4,
        winRate: 83.3,
        isInvalid: false,
        mode: .normal,
        audioClips: (1 ... 6).map { bandleClip(attempt: $0, mode: .normal) }
    )

    static let bandlePracticeChallenge = BandleChallenge(
        id: "bandle-practice-fixture",
        date: "2026-11-15T00:00:00Z",
        isInvalid: false,
        mode: .normal,
        audioClips: (1 ... 6).map { bandleClip(attempt: $0, mode: .normal) },
        replaySongId: bandleAnswer.songId
    )

    static let bandleUserData = BandleUserData(
        lastPlayed: "2026-11-14T12:00:00Z",
        streak: 4,
        gamesPlayed: 18,
        gamesWon: 15,
        lastResult: BandleResult(
            completedAt: "2026-11-14T12:05:00Z",
            won: true,
            attemptNumber: 2,
            songId: bandleAnswer.songId,
            songTitle: bandleAnswer.title,
            artist: bandleAnswer.coverArtists,
            challengeDate: "2026-11-14T00:00:00Z"
        ),
        attemptDistribution: ["1": 5, "2": 6, "3": 3, "4": 1],
        longestStreak: 8
    )

    static func bandleClip(attempt: Int, mode: BandleMode) -> BandleAudioClip {
        BandleAudioClip(
            attemptNumber: attempt,
            clipLength: attempt * 3,
            audioUrl: Bundle.main.url(forResource: "BandleFixture", withExtension: "m4a")?.absoluteString,
            mode: mode,
            effect: mode == .extreme ? .reverse : BandleAudioEffect.none
        )
    }
}
