import Foundation

extension BandleLeaderboardViewModel {
    struct Service {
        var leaderboard: @MainActor (BandleLeaderboardPeriod, BandleMode) async throws -> BandleLeaderboard
        var userData: @MainActor (BandleMode) async throws -> BandleUserData
        var history: @MainActor (BandleMode) async throws -> [BandleHistoryEntry]
        var playStatus: @MainActor (BandleMode) async throws -> BandlePlayStatus
        /// Ranks exist only for accounts; a guest's id must not be looked up.
        var isSignedIn: @MainActor () -> Bool
        var ranks: @MainActor (String) async throws -> BandleUserRanks

        static var live: Service {
            Service(
                leaderboard: { period, mode in
                    try await KaraokeAPIClient.bandleLeaderboard(period: period, mode: mode)
                },
                userData: KaraokeAPIClient.bandleUserData,
                history: { mode in
                    try await KaraokeAPIClient.bandleHistory(mode: mode)
                },
                playStatus: KaraokeAPIClient.bandlePlayStatus,
                isSignedIn: { CredentialStore.isAuthenticated },
                ranks: KaraokeAPIClient.bandleUserRanks
            )
        }

        static var uiTestFixture: Service {
            Service(
                leaderboard: { period, _ in UITestFixtures.bandleLeaderboard(for: period) },
                userData: { _ in UITestFixtures.bandleUserData },
                history: { _ in UITestFixtures.bandleHistory },
                playStatus: { _ in BandlePlayStatus(userId: "user-fixture", hasPlayed: false, inProgress: false) },
                isSignedIn: { true },
                ranks: { _ in UITestFixtures.bandleUserRanks }
            )
        }
    }
}
