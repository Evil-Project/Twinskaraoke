import AuthenticationServices
import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Security regressions")
struct SecurityRegressionTests {
    @Test("Safe song IDs keep their existing storage names")
    func safeSongStorageKeyIsBackwardCompatible() {
        #expect(SongStorageKey.component(for: "song_123-ABC") == "song_123-ABC")
    }

    @Test("Unsafe song IDs cannot become paths")
    func unsafeSongStorageKeysAreHashed() {
        let traversal = SongStorageKey.component(for: "../../Library/secret")
        let nested = SongStorageKey.component(for: "artist/song")

        #expect(traversal.hasPrefix("__nksha256_"))
        #expect(!traversal.contains("/"))
        #expect(!traversal.contains(".."))
        #expect(nested.hasPrefix("__nksha256_"))
        #expect(!nested.contains("/"))
        #expect(traversal != nested)
    }

    @Test("Unsafe song storage keys are stable and collision resistant")
    func unsafeSongStorageKeysAreStable() {
        let first = SongStorageKey.component(for: "a/b")
        #expect(first == SongStorageKey.component(for: "a/b"))
        #expect(first != SongStorageKey.component(for: "a_b"))
        #expect(first != SongStorageKey.component(for: "a?b"))
        #expect(first != SongStorageKey.component(for: first))
    }

    @Test("Oversized song IDs are hashed below filesystem limits")
    func oversizedSongStorageKeysAreHashed() {
        let longID = String(repeating: "a", count: 201)
        let component = SongStorageKey.component(for: longID)

        #expect(component.hasPrefix("__nksha256_"))
        #expect(component.utf8.count < longID.utf8.count)
    }

    @Test("Cache maintenance exclusions use on-disk storage keys")
    func cacheMaintenanceUsesStorageKeys() {
        let unsafeID = "artist/song"
        let storageKeys = SongStorageKey.components(for: [unsafeID, "safe-song"])

        #expect(storageKeys.contains(SongStorageKey.component(for: unsafeID)))
        #expect(storageKeys.contains("safe-song"))
        #expect(!storageKeys.contains(unsafeID))
    }

    @Test("Token exchange accepts supported response shapes")
    func tokenExchangeParsesSupportedResponses() {
        let json = Data(#"{"token":"nk-token"}"#.utf8)
        let alternateJSON = Data(#"{"accessToken":"alternate-token"}"#.utf8)
        let raw = Data(#""raw-token""#.utf8)

        #expect(AuthManager.exchangedToken(from: json) == "nk-token")
        #expect(AuthManager.exchangedToken(from: alternateJSON) == "alternate-token")
        #expect(AuthManager.exchangedToken(from: raw) == "raw-token")
    }

    @Test("Token exchange rejects empty or malformed responses")
    func tokenExchangeRejectsInvalidResponses() {
        #expect(AuthManager.exchangedToken(from: Data()) == nil)
        #expect(AuthManager.exchangedToken(from: Data("{}".utf8)) == nil)
        #expect(AuthManager.exchangedToken(from: Data(#"{"token":""}"#.utf8)) == nil)
        #expect(AuthManager.exchangedToken(from: Data("null".utf8)) == nil)
        #expect(AuthManager.exchangedToken(from: Data("[]".utf8)) == nil)
        #expect(AuthManager.exchangedToken(from: Data("42".utf8)) == nil)
        #expect(AuthManager.exchangedToken(from: Data("<html>error</html>".utf8)) == nil)
    }

    @Test("API path segments are encoded exactly once")
    func apiPathSegmentsAreEncodedExactlyOnce() throws {
        let request = try KaraokeAPIClient.request(
            pathSegments: ["api", "songs", "a b/c%?", "lyrics"],
            readToken: { nil }
        )

        #expect(request.url?.absoluteString.contains("/api/songs/a%20b%2Fc%25%3F/lyrics") == true)
        #expect(request.url?.absoluteString.contains("%2520") == false)
    }

    @Test("API path segments reject navigation components")
    func apiPathSegmentsRejectNavigation() {
        #expect(throws: KaraokeAPIClient.APIError.self) {
            try KaraokeAPIClient.request(pathSegments: ["api", ".", "songs"])
        }
        #expect(throws: KaraokeAPIClient.APIError.self) {
            try KaraokeAPIClient.request(pathSegments: ["api", "..", "songs"])
        }
    }

    @Test("Translation credentials are limited to first-party HTTPS origins")
    func translationCredentialOriginsAreAllowlisted() throws {
        let primary = try #require(URL(string: "https://api.neurokaraoke.com/api/translate"))
        let china = try #require(URL(string: "https://api.neurokaraoke.com.cn/api/translate"))
        let thirdParty = try #require(URL(string: "https://example.com/translate"))
        let lookalike = try #require(URL(string: "https://api.neurokaraoke.com.example.com/translate"))
        let insecure = try #require(URL(string: "http://api.neurokaraoke.com/api/translate"))

        #expect(LyricsTranslationService.isFirstPartyEndpoint(primary))
        #expect(LyricsTranslationService.isFirstPartyEndpoint(china))
        #expect(!LyricsTranslationService.isFirstPartyEndpoint(thirdParty))
        #expect(!LyricsTranslationService.isFirstPartyEndpoint(lookalike))
        #expect(!LyricsTranslationService.isFirstPartyEndpoint(insecure))
    }

    @Test("Web authentication cancellation maps to a silent cancellation")
    func webAuthenticationCancellationIsMapped() {
        let error = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        )
        let mapped = AuthManager.mappedWebAuthenticationError(error)

        guard let authError = mapped as? AuthManager.AuthError else {
            Issue.record("Expected AuthError.cancelled")
            return
        }
        guard case .cancelled = authError else {
            Issue.record("Expected AuthError.cancelled")
            return
        }
    }

    @Test("Only complete credential commits restore a session")
    func incompleteCredentialCommitsAreRejected() {
        #expect(AuthManager.persistedSessionIsComplete(
            token: "token", username: "user", commitMarker: true
        ))
        #expect(AuthManager.persistedSessionIsComplete(
            token: "token", username: "user", commitMarker: nil
        ))
        #expect(!AuthManager.persistedSessionIsComplete(
            token: "token", username: "user", commitMarker: false
        ))
        #expect(!AuthManager.persistedSessionIsComplete(
            token: "token", username: nil, commitMarker: true
        ))
    }

    @Test("Only staged download directories match startup cleanup")
    func pendingDownloadDeletionNamesAreScoped() {
        #expect(DownloadManager.isPendingDeletionDirectoryName(
            "Downloads.pending-delete-123"
        ))
        #expect(!DownloadManager.isPendingDeletionDirectoryName("Downloads"))
        #expect(!DownloadManager.isPendingDeletionDirectoryName("Downloads.backup"))
    }
}
