import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Bandle response decoding")
struct BandleModelDecodingTests {
    @Test("Today's challenge decodes clips without exposing an answer")
    func decodesChallenge() throws {
        let challenge = try JSONDecoder().decode(BandleChallenge.self, from: Data(#"""
            {
              "id": "daily-1", "date": "2026-11-15T00:00:00Z", "totalPlays": 40,
              "totalWins": 32, "averageAttempt": 2.5, "winRate": 80,
              "isInvalid": false, "mode": 1,
              "audioClips": [{"attemptNumber": 1, "clipLength": 3, "audioUrl": "https://example.com/1.mp3", "mode": 1, "effect": 1}],
              "replaySongId": null
            }
            """#.utf8))

        #expect(challenge.id == "daily-1")
        #expect(challenge.mode == .extreme)
        #expect(challenge.audioClips == [
            BandleAudioClip(
                attemptNumber: 1,
                clipLength: 3,
                audioUrl: "https://example.com/1.mp3",
                mode: .extreme,
                effect: .reverse
            ),
        ])
        #expect(challenge.replaySongId == nil)
    }

    @Test("Play status keeps resumable attempts and their required clip lengths")
    func decodesProgress() throws {
        let status = try JSONDecoder().decode(BandlePlayStatus.self, from: Data(#"""
            {
              "userId": "user-1", "hasPlayed": false, "mode": 0, "inProgress": true,
              "progress": {
                "currentAttemptNumber": 2,
                "attempts": [{"attemptNumber": 1, "status": 2, "guessedSongId": null, "clipLength": 3}]
              }
            }
            """#.utf8))

        #expect(status.inProgress == true)
        #expect(status.progress?.currentAttemptNumber == 2)
        #expect(status.progress?.attempts == [
            BandleAttempt(clipLength: 3, attemptNumber: 1, status: .skipped),
        ])
    }

    @Test("Completion decodes answer metadata, result artwork and reimbursement")
    func decodesResult() throws {
        let result = try JSONDecoder().decode(BandleResult.self, from: Data(#"""
            {
              "won": true, "attemptNumber": 1, "songId": "song-1", "songTitle": "Test Song",
              "artist": "Test Artist", "completedAt": "2026-11-15T13:00:00Z",
              "mediaListDTO": {"cloudflareId": "art-1", "absolutePath": "image/test.jpg"},
              "attempts": [{"attemptNumber": 1, "status": 0, "guessedSongId": "song-1", "clipLength": 3}],
              "invalidChallengeReimbursement": 1000
            }
            """#.utf8))

        #expect(result.won == true)
        #expect(result.songTitle == "Test Song")
        #expect(result.mediaListDTO?.cloudflareId == "art-1")
        #expect(result.invalidChallengeReimbursement == 1000)
        #expect(result.attempts?.first?.status == .correct)
    }

    @Test("History and each leaderboard period tolerate missing optional fields")
    func decodesHistoryAndLeaderboards() throws {
        let history = try JSONDecoder().decode([BandleHistoryEntry].self, from: Data(#"""
            [{"id": "game-1", "mode": 0, "won": false, "attemptNumber": 6,
              "dailySong": {"songTitle": "Old Song", "artist": "Artist"}}]
            """#.utf8))
        let leaderboard = try JSONDecoder().decode(BandleLeaderboard.self, from: Data(#"""
            {"weekNumber": 46, "year": 2026, "mode": 0,
             "entries": [{"userId": "user-1", "rank": 1, "totalScore": 12000}]}
            """#.utf8))

        #expect(history.first?.id == "game-1")
        #expect(history.first?.dailySong?.songTitle == "Old Song")
        #expect(leaderboard.weekNumber == 46)
        #expect(leaderboard.entries?.first?.totalScore == 12000)
    }

    @Test(
        "Server time spans become durations",
        arguments: [
            ("00:01:12", Duration.seconds(72)),
            ("00:00:09.5000000", Duration.milliseconds(9500)),
            ("1.02:03:04", Duration.seconds(93784)),
        ]
    )
    func parsesTimeSpan(text: String, expected: Duration) {
        #expect(BandleTimeSpan.duration(from: text) == expected)
    }

    @Test("Malformed time spans are ignored", arguments: ["", "abc", "12", "00:61:00", "-00:00:05"])
    func rejectsMalformedTimeSpan(text: String) {
        #expect(BandleTimeSpan.duration(from: text) == nil)
    }
}
