import Foundation

nonisolated enum LyricsRepository {
    static func request(songID: String, readToken: () throws -> String? = CredentialStore.requestToken) throws -> URLRequest {
        var request = try KaraokeAPIClient.request(pathSegments: ["api", "songs", songID, "lyrics"], readToken: readToken)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        return request
    }

    static func decode(_ data: Data) throws -> [LyricLine] {
        try JSONDecoder().decode([RawLyricLine].self, from: data).compactMap { line in
            guard let time = TimeSpanParser.parse(line.time) else { return nil }
            return LyricLine(time: time, text: line.text)
        }.sorted { $0.time < $1.time }
    }

    static func lyrics(songID: String) async throws -> [LyricLine] {
        let request = try request(songID: songID)
        let data = try await KaraokeAPIClient.data(for: request)
        try Task.checkCancellation()
        return try decode(data)
    }
}
