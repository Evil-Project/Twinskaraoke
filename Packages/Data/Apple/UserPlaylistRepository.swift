import Foundation

/// Shared wire operations. Platform managers own presentation, refreshes and counts.
nonisolated enum UserPlaylistRepository {
    static func playlists() async throws -> [UserPlaylist] {
        let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
        let data = try await KaraokeAPIClient.data(for: request)
        return try JSONDecoder().decode([UserPlaylist].self, from: data)
    }

    static func createRequest(name: String, description: String?, isPublic: Bool,
                              readToken: () throws -> String? = CredentialStore.requestToken) throws -> URLRequest {
        var body: [String: Any] = ["Name": name, "IsPublic": isPublic, "IsSetList": false]
        if let description, !description.isEmpty { body["Description"] = description }
        var request = try KaraokeAPIClient.request(path: "/api/playlist/save", readToken: readToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func create(name: String, description: String?, isPublic: Bool) async throws {
        let request = try createRequest(name: name, description: description, isPublic: isPublic)
        _ = try await KaraokeAPIClient.data(for: request)
    }

    static func addSong(_ songID: String, to playlistID: String) async throws {
        var request = try KaraokeAPIClient.request(
            pathSegments: ["api", "user", "playlists", playlistID],
            queryItems: [URLQueryItem(name: "songId", value: songID)])
        request.httpMethod = "PUT"
        _ = try await KaraokeAPIClient.data(for: request)
        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
    }

    static func removeSong(_ songID: String, from playlistID: String,
        execute: @Sendable (URLRequest) async throws -> Data = { try await KaraokeAPIClient.data(for: $0) },
        readToken: @Sendable () throws -> String? = CredentialStore.requestToken
    ) async throws {
        var request = try KaraokeAPIClient.request(pathSegments: ["api", "playlist", playlistID, "song", songID], readToken: readToken)
        request.httpMethod = "DELETE"
        do { _ = try await execute(request) }
        catch KaraokeAPIClient.APIError.httpStatus(404) {
            // A previously removed song is already in the requested final state.
        }
        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
    }

    static func moveSong(_ songID: String, from oldOrder: Int, to newOrder: Int, in playlistID: String) async throws {
        let request = try KaraokeAPIClient.jsonArrayRequest(
            pathSegments: ["api", "user", "playlists", playlistID, "save-order"],
            body: KaraokeAPIClient.songMovePayload(songID: songID, from: oldOrder, to: newOrder))
        _ = try await KaraokeAPIClient.data(for: request)
        await KaraokeAPIClient.invalidatePlaylistDetail(id: playlistID)
    }
}
