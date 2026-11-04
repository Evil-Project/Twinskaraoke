import Foundation

/// Reports plays to `PUT /api/songs/playCount/{id}`, and remembers which
/// playlist the current queue came from so plays from it count toward that
/// playlist, as they do on the website (`?playlistId=`).
@MainActor
final class PlayCountReporter {
    /// Sends one report. Fire and forget: the result is discarded, so a retry
    /// would only cost requests. Tests replace it to capture the requests.
    var send: @Sendable (URLRequest) async -> Void = { request in
        _ = try? await KaraokeAPIClient.data(for: request, allowsRetry: false)
    }

    /// Reads the sign-in token for each report. Tests replace it: the unsigned
    /// test host has no Keychain access, and a report whose token can't be
    /// read is skipped.
    var readToken: @Sendable () throws -> String? = { try CredentialStore.requestToken() }

    private var playlistID: String?
    private var playlistSongIDs: Set<String> = []

    /// Call whenever a new queue starts. `playlistID` is nil for a queue that
    /// didn't come from a playlist (search, home, autoplay, companion, …).
    /// IDs starting with `__`, such as Favorites, are local placeholders the
    /// server doesn't know, so they are never sent.
    func queueStarted(fromPlaylist playlistID: String?, songs: [Song]) {
        if let playlistID, !playlistID.isEmpty, !playlistID.hasPrefix("__") {
            self.playlistID = playlistID
            playlistSongIDs = Set(songs.map(\.id))
        } else {
            self.playlistID = nil
            playlistSongIDs = []
        }
    }

    /// The playlist a play of `songID` counts toward. A song added to the
    /// queue with Play Next or Play Last isn't part of it.
    func playlistID(for songID: String) -> String? {
        playlistSongIDs.contains(songID) ? playlistID : nil
    }

    func report(songID: String) {
        let playlistID = playlistID(for: songID)
        let send = send
        let readToken = readToken
        Task {
            guard let request = try? Self.request(songID: songID, playlistID: playlistID, readToken: readToken) else { return }
            await send(request)
        }
    }

    nonisolated static func request(
        songID: String,
        playlistID: String?,
        readToken: () throws -> String? = CredentialStore.requestToken
    ) throws -> URLRequest {
        var request = try KaraokeAPIClient.request(
            pathSegments: ["api", "songs", "playCount", songID],
            queryItems: playlistID.map { [URLQueryItem(name: "playlistId", value: $0)] } ?? [],
            readToken: readToken
        )
        request.httpMethod = "PUT"
        return request
    }
}
