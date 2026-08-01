import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Favorite song decoding")
struct FavoriteSongDecodingTests {
    @Test("Valid empty favorite payloads stay empty")
    func validEmptyPayloads() throws {
        let payloads = [
            "[]",
            #"{"items":[]}"#,
            #"{"favorites":[]}"#,
        ]

        for payload in payloads {
            let songs = try KaraokeAPIClient.decodeFavoriteSongs(from: Data(payload.utf8))
            #expect(songs.isEmpty)
        }
    }

    @Test("A malformed nonempty favorite envelope is rejected")
    func malformedNonemptyEnvelopeThrows() {
        let payload = #"[{"favoriteId":"favorite-1","song":{"unexpected":true}}]"#

        #expect(throws: KaraokeAPIClient.APIError.decodeFailed) {
            try KaraokeAPIClient.decodeFavoriteSongs(from: Data(payload.utf8))
        }
    }

    @Test("Lossy favorite arrays preserve valid songs")
    func partiallyValidFavoriteArrayPreservesSongs() throws {
        let payload =
            #"[{"song":{"id":"song-1","title":"First","duration":180,"absolutePath":"audio/first.mp3"}},{"song":{"unexpected":true}}]"#

        let songs = try KaraokeAPIClient.decodeFavoriteSongs(from: Data(payload.utf8))

        #expect(songs.map(\.id) == ["song-1"])
    }

    @Test("Unsupported container shapes are rejected")
    func unsupportedContainersThrow() {
        let payloads = [
            "{}",
            #"{"items":[{"unexpected":true}]}"#,
            #"{"favorites":"not-an-array"}"#,
            "not-json",
        ]

        for payload in payloads {
            #expect(throws: KaraokeAPIClient.APIError.decodeFailed) {
                try KaraokeAPIClient.decodeFavoriteSongs(from: Data(payload.utf8))
            }
        }
    }
}
