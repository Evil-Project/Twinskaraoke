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
        }, toggleSong: { _ in false })

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
        }, toggleSong: { _ in false })

        manager.loadIfNeeded()
        try await waitUntil { calls.count == 1 }
        try await Task.sleep(for: .milliseconds(20))

        manager.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(calls.count == 1)
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
