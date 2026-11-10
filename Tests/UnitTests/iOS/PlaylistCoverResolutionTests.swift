import Foundation
import Testing
@testable import Twinskaraoke

/// A tile shows its "no cover" glyph only once the loader knows there is no
/// cover, not while the answer is still on its way.
@MainActor
struct PlaylistCoverResolutionTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out")
    }

    @Test func aPlaylistWithoutCoversResolvesEmpty() async throws {
        var pending: CheckedContinuation<Data, Error>?
        let loader = PlaylistCoverLoader { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        loader.load(playlistID: "a")
        try await waitUntil { pending != nil }
        #expect(!loader.hasResolved)
        #expect(loader.artworkURLs.isEmpty)

        pending?.resume(returning: Data(#"{"id":"a","name":"A"}"#.utf8))
        try await waitUntil { loader.hasResolved }
        #expect(loader.artworkURLs.isEmpty)
    }

    @Test func aFailedLoadResolvesToo() async throws {
        let loader = PlaylistCoverLoader { _ in throw URLError(.badServerResponse) }
        loader.load(playlistID: "a")
        try await waitUntil { loader.hasResolved }
        #expect(loader.artworkURLs.isEmpty)
    }

    @Test func anotherPlaylistStartsUnresolved() async throws {
        var pending: [CheckedContinuation<Data, Error>] = []
        let loader = PlaylistCoverLoader { _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        loader.load(playlistID: "a")
        try await waitUntil { pending.count == 1 }
        pending[0].resume(returning: Data(#"{"id":"a","name":"A"}"#.utf8))
        try await waitUntil { loader.hasResolved }

        loader.load(playlistID: "b")
        #expect(!loader.hasResolved)
        try await waitUntil { pending.count == 2 }
        pending[1].resume(throwing: URLError(.cancelled))
    }
}
