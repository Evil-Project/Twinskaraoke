import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Favorites load cancellation")
@MainActor
struct FavoritesLoadCancellationTests {
    @Test("A load cancelled by a newer request does not start the retry backoff", arguments: [
        URLError(.cancelled) as Error,
        CancellationError() as Error,
    ])
    func cancelledLoadDoesNotBackOff(error: Error) async throws {
        let song = UITestFixtures.song(id: "starred", title: "Starred", artist: "Artist")
        let calls = CallLog()
        let manager = FavoritesManager(authenticated: { true }, fetchSongs: {
            calls.count += 1
            if calls.count == 1 { throw error }
            return [song]
        }, setFavorite: { _, _ in false })

        manager.loadIfNeeded()
        try await waitUntil { calls.count == 1 }
        try await Task.sleep(for: .milliseconds(20))

        manager.loadIfNeeded()
        try await waitUntil { manager.isFavorite(song.id) }
        #expect(calls.count == 2)
    }

    @Test("A load that genuinely fails still backs off")
    func failedLoadBacksOff() async throws {
        let calls = CallLog()
        let manager = FavoritesManager(authenticated: { true }, fetchSongs: {
            calls.count += 1
            throw URLError(.notConnectedToInternet)
        }, setFavorite: { _, _ in false })

        manager.loadIfNeeded()
        try await waitUntil { calls.count == 1 }
        try await Task.sleep(for: .milliseconds(20))

        manager.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(calls.count == 1)
    }

    @Test("Starring adds and unstarring removes, rather than repeating one toggle write")
    func writesCarryTheTargetState() async throws {
        let song = UITestFixtures.song(id: "starred", title: "Starred", artist: "Artist")
        let writes = WriteLog()
        let manager = FavoritesManager(authenticated: { true }, fetchSongs: { [] }, setFavorite: { _, favorite in
            writes.values.append(favorite)
            return true
        })

        await manager.toggle(songID: song.id)?.value
        #expect(manager.isFavorite(song.id))
        await manager.toggle(songID: song.id)?.value
        #expect(!manager.isFavorite(song.id))
        #expect(await manager.add(songID: song.id))
        #expect(await manager.remove(songID: song.id))
        #expect(writes.values == [true, false, true, false])
    }

    @Test("Starring sends PUT and unstarring sends DELETE to the song's favorite route")
    func favoriteRequestsUseMatchingMethods() throws {
        let add = try FavoritesManager.favoriteRequest(songID: "song-id", favorite: true, readToken: { "test-token" })
        let remove = try FavoritesManager.favoriteRequest(songID: "song-id", favorite: false, readToken: { "test-token" })

        #expect(add.httpMethod == "PUT")
        #expect(remove.httpMethod == "DELETE")
        for request in [add, remove] {
            #expect(request.url?.path == "/api/user/favorites/song-id")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition not met in time")
    }
}

@MainActor
private final class CallLog {
    var count = 0
}

@MainActor
private final class WriteLog {
    var values: [Bool] = []
}
