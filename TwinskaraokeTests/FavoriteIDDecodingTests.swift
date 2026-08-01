import Foundation
import Testing
@testable import Twinskaraoke

private actor FavoriteIDPayloadSequence {
    private var payloads: [Data]

    init(_ payloads: [String]) {
        self.payloads = payloads.map { Data($0.utf8) }
    }

    func load() throws -> [String] {
        guard !payloads.isEmpty else {
            throw KaraokeAPIClient.APIError.decodeFailed
        }
        return try FavoritesManager.decodeFavoriteIDs(from: payloads.removeFirst())
    }
}

@MainActor
@Suite("Favorite ID decoding")
struct FavoriteIDDecodingTests {
    @Test("Valid empty payloads remain successful empty results")
    func validEmptyPayloads() throws {
        let payloads = [
            "[]",
            #"{"favorites":[]}"#,
            #"{"items":[]}"#,
        ]

        for payload in payloads {
            let decoded = try FavoritesManager.decodeFavoriteIDs(from: Data(payload.utf8))
            #expect(decoded.isEmpty)
        }
    }

    @Test("Supported payload shapes preserve every favorite ID")
    func supportedPayloads() throws {
        #expect(
            try FavoritesManager.decodeFavoriteIDs(
                from: Data(#"["song-a","song-b"]"#.utf8)
            ) == ["song-a", "song-b"]
        )
        #expect(
            try FavoritesManager.decodeFavoriteIDs(
                from: Data(#"[{"id":"song-a"},{"songId":"song-b"}]"#.utf8)
            ) == ["song-a", "song-b"]
        )
        #expect(
            try FavoritesManager.decodeFavoriteIDs(
                from: Data(#"{"favorites":[{"id":"song-a"}]}"#.utf8)
            ) == ["song-a"]
        )
        #expect(
            try FavoritesManager.decodeFavoriteIDs(
                from: Data(#"{"items":["song-b"]}"#.utf8)
            ) == ["song-b"]
        )
    }

    @Test("Malformed nonempty payloads fail instead of clearing favorites")
    func malformedNonemptyPayloads() {
        let payloads = [
            "not-json",
            "{}",
            #"{"favorites":null}"#,
            #"{"favorites":[{"unexpected":"song-a"}]}"#,
            #"[{"id":"song-a"},{"unexpected":"song-b"}]"#,
            #"{"unexpected":[]}"#,
            #"[""]"#,
        ]

        for payload in payloads {
            #expect(throws: KaraokeAPIClient.APIError.decodeFailed) {
                try FavoritesManager.decodeFavoriteIDs(from: Data(payload.utf8))
            }
        }
    }

    @Test("A malformed reload preserves the last successful favorite IDs")
    func malformedReloadPreservesExistingFavorites() async {
        let payloads = FavoriteIDPayloadSequence([
            #"["existing-song"]"#,
            #"{"favorites":[{"unexpected":"replacement"}]}"#,
        ])
        let manager = FavoritesManager(
            favoriteIDsLoader: { try await payloads.load() },
            toggleSender: { _, _ in true },
            sessionScopeProvider: { .authenticated(token: "token") }
        )

        let initialLoad = manager.reload()
        await initialLoad?.value
        #expect(manager.favoriteIDs == ["existing-song"])

        let malformedReload = manager.reload()
        await malformedReload?.value
        #expect(manager.favoriteIDs == ["existing-song"])
    }
}
