import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Bandle API requests")
struct KaraokeAPIClientBandleTests {
    @Test("Today carries ephemeral and mode as documented")
    func buildsTodayRequest() throws {
        let request = try KaraokeAPIClient.bandleTodayRequest(ephemeral: true, mode: .extreme, readToken: { nil })
        let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)

        #expect(components?.path == "/api/dailychallenge/today")
        #expect(Set(components?.queryItems ?? []) == [
            URLQueryItem(name: "ephemeral", value: "true"),
            URLQueryItem(name: "mode", value: "1"),
        ])
        #expect(request.value(forHTTPHeaderField: "x-guest-id")?.isEmpty == false)
    }

    @Test("A start uses one JSON POST with leaderboard exclusion and mode")
    func buildsStartRequest() throws {
        let request = try KaraokeAPIClient.bandleStartRequest(
            excludeFromLeaderboard: true,
            mode: .extreme,
            readToken: { "token" }
        )
        let body = try jsonObject(request.httpBody)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/dailychallenge/start")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(body["excludeFromLeaderboard"] as? Bool == true)
        #expect(body["mode"] as? Int == 1)
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems == [BandleMode.extreme.queryItem])
    }

    @Test("A skip has a null song ID and completion retains ordered attempts")
    func buildsAttemptAndCompletionRequests() throws {
        let skip = try KaraokeAPIClient.bandleAttemptRequest(
            BandleAttemptInput(attemptNumber: 2, isSkip: true),
            readToken: { nil }
        )
        let skipBody = try jsonObject(skip.httpBody)
        #expect(skipBody["isSkip"] as? Bool == true)
        #expect(skipBody["guessedSongId"] is NSNull)

        let attempts = [
            BandleAttempt(clipLength: 3, attemptNumber: 1, status: .skipped),
            BandleAttempt(
                clipLength: 6,
                attemptNumber: 2,
                status: .correct,
                guessedSongId: "song-1",
                guessedSongTitle: "Song"
            ),
        ]
        let complete = try KaraokeAPIClient.bandleCompleteRequest(
            BandleCompletionInput(
                won: true,
                attemptNumber: 2,
                songId: "song-1",
                songTitle: "Song",
                artist: "Artist",
                attempts: attempts
            ),
            readToken: { nil }
        )
        let completeBody = try jsonObject(complete.httpBody)
        let sentAttempts = completeBody["attempts"] as? [[String: Any]]

        #expect(completeBody["won"] as? Bool == true)
        #expect(sentAttempts?.count == 2)
        #expect(sentAttempts?.first?["status"] as? Int == 2)
        #expect(sentAttempts?.last?["guessedSongId"] as? String == "song-1")
    }

    @Test("Replay song and user-rank path values use the documented fields")
    func buildsReplayAndRankRequests() throws {
        let songs = try KaraokeAPIClient.bandleGuessableSongsRequest(
            replaySongId: "song id/1",
            mode: .normal,
            readToken: { nil }
        )
        let items = URLComponents(url: try #require(songs.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains(URLQueryItem(name: "replaySongId", value: "song id/1")) == true)

        let rank = try KaraokeAPIClient.request(
            pathSegments: ["api", "dailychallenge", "leaderboard", "user", "user id/1", "ranks"],
            readToken: { nil }
        )
        #expect(rank.url?.path == "/api/dailychallenge/leaderboard/user/user id/1/ranks")
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try #require(data))
        return try #require(object as? [String: Any])
    }
}
