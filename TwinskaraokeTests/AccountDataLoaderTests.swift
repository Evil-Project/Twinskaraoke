import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Account data loading")
struct AccountDataLoaderTests {
    @Test("An HTTP failure preserves the successful profile response")
    func partialSuccessPreservesProfile() async throws {
        let loader = AccountDataLoader { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer captured-token")

            if url.path == "/api/badge/profile" {
                return (
                    Data(
                        """
                        {
                          "profile": { "displayName": "Updated User" },
                          "badges": []
                        }
                        """.utf8
                    ),
                    try response(for: url, statusCode: 200)
                )
            }

            return (
                Data("unavailable".utf8),
                try response(for: url, statusCode: 503)
            )
        }

        let result = await loader.load(token: "captured-token")

        #expect(result.profileResponse?.profile.displayName == "Updated User")
        #expect(result.uploadLimits == nil)
        #expect(result.failures == [.uploadLimits: .httpStatus(503)])
    }

    @Test("A decoding failure preserves valid upload limits")
    func decodingFailurePreservesUploadLimits() async throws {
        let loader = AccountDataLoader { request in
            let url = try #require(request.url)
            if url.path == "/api/badge/profile" {
                return (
                    Data("{\"profile\":{\"displayName\":42}}".utf8),
                    try response(for: url, statusCode: 200)
                )
            }

            return (
                Data(
                    """
                    {
                      "maxSongs": 100,
                      "maxStorageBytes": 1000000,
                      "usedStorageBytes": 250000,
                      "currentSongCount": 12,
                      "currentPlaylistCount": 3,
                      "playlistLimit": 20,
                      "songPerPlaylistLimit": 50
                    }
                    """.utf8
                ),
                try response(for: url, statusCode: 200)
            )
        }

        let result = await loader.load(token: "captured-token")

        #expect(result.profileResponse == nil)
        #expect(result.uploadLimits?.currentSongCount == 12)
        #expect(result.failures == [.profile: .decoding])
    }

    @Test("Load ownership rejects logout, account switches, and newer loads")
    func ownershipRejectsStaleSessions() {
        let ownership = AccountLoadOwnership(token: "old-token", generation: 4)

        #expect(ownership.isCurrent(token: "old-token", generation: 4))
        #expect(!ownership.isCurrent(token: nil, generation: 4))
        #expect(!ownership.isCurrent(token: "new-token", generation: 4))
        #expect(!ownership.isCurrent(token: "old-token", generation: 5))
    }

    private func response(for url: URL, statusCode: Int) throws -> HTTPURLResponse {
        try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }
}
