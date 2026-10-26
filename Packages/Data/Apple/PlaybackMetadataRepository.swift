import Foundation

nonisolated enum PlaybackMetadataRepository {
    static func reportPlay(songID: String) async {
        guard var request = try? KaraokeAPIClient.request(pathSegments: ["api", "songs", "playCount", songID]) else { return }
        request.httpMethod = "PUT"
        _ = try? await KaraokeAPIClient.data(for: request, allowsRetry: false)
    }

    static func enrichedSong(_ song: Song) async -> Song? {
        let body: [String: Any] = ["page": 1, "pageSize": 1, "search": song.title]
        if let request = try? KaraokeAPIClient.jsonRequest(path: "/api/songs", body: body),
           let data = try? await KaraokeAPIClient.data(for: request) {
            return matchingSong(in: data, id: song.id)
        }
        guard let request = try? KaraokeAPIClient.request(path: "/api/explore/trendings",
            queryItems: [URLQueryItem(name: "days", value: "all")]),
              let data = try? await KaraokeAPIClient.data(for: request) else { return nil }
        return matchingSong(in: data, id: song.id)
    }

    private static func matchingSong(in data: Data, id: String) -> Song? {
        if let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
           let match = response.items.first(where: { $0.id == id }) { return match }
        return (try? JSONDecoder().decode([Song].self, from: data))?.first { $0.id == id }
    }
}
