import Foundation

nonisolated extension KaraokeAPIClient {
    private static let bandlePath = "/api/dailychallenge"

    static func bandleTodayRequest(
        ephemeral: Bool = false,
        mode: BandleMode = .normal,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        try request(
            path: "\(bandlePath)/today",
            queryItems: [
                URLQueryItem(name: "ephemeral", value: String(ephemeral).lowercased()),
                mode.queryItem,
            ],
            readToken: readToken
        )
    }

    static func bandleToday(ephemeral: Bool = false, mode: BandleMode = .normal) async throws -> BandleChallenge {
        let data = try await data(for: bandleTodayRequest(ephemeral: ephemeral, mode: mode))
        return try JSONDecoder().decode(BandleChallenge.self, from: data)
    }

    static func bandleStartRequest(
        excludeFromLeaderboard: Bool = false,
        mode: BandleMode = .normal,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        try bandleWriteRequest(
            path: "\(bandlePath)/start",
            queryItems: [mode.queryItem],
            body: [
                "excludeFromLeaderboard": excludeFromLeaderboard,
                "mode": mode.rawValue,
            ],
            readToken: readToken
        )
    }

    static func bandleStart(
        excludeFromLeaderboard: Bool = false,
        mode: BandleMode = .normal
    ) async throws -> BandleSession {
        let request = try bandleStartRequest(excludeFromLeaderboard: excludeFromLeaderboard, mode: mode)
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleSession.self, from: data)
    }

    static func bandleAudioRequest(
        attemptNumber: Int,
        mode: BandleMode = .normal,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        try request(
            pathSegments: ["api", "dailychallenge", "audio", String(attemptNumber)],
            queryItems: [mode.queryItem],
            readToken: readToken
        )
    }

    static func bandleAudio(attemptNumber: Int, mode: BandleMode = .normal) async throws -> BandleAudioClip {
        let data = try await data(for: bandleAudioRequest(attemptNumber: attemptNumber, mode: mode))
        return try JSONDecoder().decode(BandleAudioClip.self, from: data)
    }

    static func bandleGuessableSongsRequest(
        limit: Int = 300,
        replaySongId: String? = nil,
        mode: BandleMode = .normal,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit)), mode.queryItem]
        if let replaySongId {
            queryItems.append(URLQueryItem(name: "replaySongId", value: replaySongId))
        }
        return try request(
            path: "\(bandlePath)/songs",
            queryItems: queryItems,
            readToken: readToken
        )
    }

    static func bandleGuessableSongs(
        limit: Int = 300,
        replaySongId: String? = nil,
        mode: BandleMode = .normal
    ) async throws -> [BandleGuessSong] {
        let request = try bandleGuessableSongsRequest(limit: limit, replaySongId: replaySongId, mode: mode)
        let data = try await data(for: request)
        return try JSONDecoder().decode([BandleGuessSong].self, from: data)
    }

    static func bandleAttemptRequest(
        _ input: BandleAttemptInput,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        try bandleWriteRequest(
            path: "\(bandlePath)/attempt",
            body: [
                "attemptNumber": input.attemptNumber,
                "guessedSongId": input.guessedSongId ?? NSNull(),
                "isSkip": input.isSkip,
                "mode": input.mode.rawValue,
            ],
            readToken: readToken
        )
    }

    static func bandleSubmitAttempt(_ input: BandleAttemptInput) async throws -> BandleAttempt {
        let request = try bandleAttemptRequest(input)
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleAttempt.self, from: data)
    }

    static func bandleCompleteRequest(
        _ input: BandleCompletionInput,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        let encodedAttempts = try JSONEncoder().encode(input.attempts)
        let attemptObjects = try JSONSerialization.jsonObject(with: encodedAttempts)
        guard attemptObjects is [[String: Any]] else { throw APIError.invalidBody }
        var body: [String: Any] = [
            "won": input.won,
            "attemptNumber": input.attemptNumber,
            "songId": input.songId ?? NSNull(),
            "songTitle": input.songTitle ?? NSNull(),
            "artist": input.artist ?? NSNull(),
            "attempts": attemptObjects,
            "mode": input.mode.rawValue,
        ]
        // Optional in the API; left out when unknown so the server keeps the
        // choice recorded at /start.
        if let exclude = input.excludeFromLeaderboard {
            body["excludeFromLeaderboard"] = exclude
        }
        return try bandleWriteRequest(path: "\(bandlePath)/complete", body: body, readToken: readToken)
    }

    static func bandleComplete(_ input: BandleCompletionInput) async throws -> BandleResult {
        let request = try bandleCompleteRequest(input)
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleResult.self, from: data)
    }

    static func bandlePlayStatus(mode: BandleMode = .normal) async throws -> BandlePlayStatus {
        let request = try request(path: "\(bandlePath)/has-played", queryItems: [mode.queryItem])
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandlePlayStatus.self, from: data)
    }

    static func bandleUserData(mode: BandleMode = .normal) async throws -> BandleUserData {
        let request = try request(path: "\(bandlePath)/user/data", queryItems: [mode.queryItem])
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleUserData.self, from: data)
    }

    static func bandleHistory(limit: Int = 30, mode: BandleMode = .normal) async throws -> [BandleHistoryEntry] {
        let request = try request(
            path: "\(bandlePath)/history",
            queryItems: [URLQueryItem(name: "limit", value: String(limit)), mode.queryItem]
        )
        let data = try await data(for: request)
        return try JSONDecoder().decode([BandleHistoryEntry].self, from: data)
    }

    static func bandleGlobalStatsToday() async throws -> BandleGlobalStats {
        let data = try await data(for: request(path: "\(bandlePath)/stats/global/today"))
        return try JSONDecoder().decode(BandleGlobalStats.self, from: data)
    }

    static func bandleLeaderboard(
        period: BandleLeaderboardPeriod = .today,
        limit: Int = 100,
        mode: BandleMode = .normal
    ) async throws -> BandleLeaderboard {
        let request = try request(
            path: "\(bandlePath)/leaderboard/\(period.rawValue)",
            queryItems: [URLQueryItem(name: "limit", value: String(limit)), mode.queryItem]
        )
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleLeaderboard.self, from: data)
    }

    static func bandleUserRanks(userId: String) async throws -> BandleUserRanks {
        let request = try request(
            pathSegments: ["api", "dailychallenge", "leaderboard", "user", userId, "ranks"]
        )
        let data = try await data(for: request)
        return try JSONDecoder().decode(BandleUserRanks.self, from: data)
    }

    private static func bandleWriteRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any],
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        guard JSONSerialization.isValidJSONObject(body) else { throw APIError.invalidBody }
        var request = try request(path: path, queryItems: queryItems, readToken: readToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
