import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
private final class FakeBandleLeaderboardService {
    struct Call: Equatable {
        let period: BandleLeaderboardPeriod
        let mode: BandleMode
    }

    private(set) var calls: [Call] = []
    private(set) var rankCalls: [String] = []
    var userId: String? = "user-fixture"
    var isSignedIn = true
    var shouldFail = false
    var shouldFailRanks = false
    var shouldFailUserData = false

    var service: BandleLeaderboardViewModel.Service {
        BandleLeaderboardViewModel.Service(
            leaderboard: { period, mode in
                try Task.checkCancellation()
                self.calls.append(Call(period: period, mode: mode))
                if self.shouldFail { throw URLError(.notConnectedToInternet) }
                return UITestFixtures.bandleLeaderboard(for: period)
            },
            userData: { _ in
                if self.shouldFailUserData { throw URLError(.notConnectedToInternet) }
                return UITestFixtures.bandleUserData
            },
            history: { _ in UITestFixtures.bandleHistory },
            playStatus: { _ in BandlePlayStatus(userId: self.userId, hasPlayed: false, inProgress: false) },
            isSignedIn: { self.isSignedIn },
            ranks: { userId in
                self.rankCalls.append(userId)
                if self.shouldFailRanks { throw URLError(.badServerResponse) }
                return UITestFixtures.bandleUserRanks
            }
        )
    }
}

@MainActor
@Suite("Bandle leaderboard view model")
struct BandleLeaderboardViewModelTests {
    @Test("Loading fetches stats, history and the signed-in user's ranks once")
    func loadsDashboard() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(fake.calls == [.init(period: .today, mode: .normal)])
        #expect(fake.rankCalls == ["user-fixture"])
        #expect(model.userData?.streak == 4)
        #expect(model.history.map(\.id) == ["bandle-game-2", "bandle-game-1"])
        #expect(model.currentUserRank == 3)
    }

    @Test("Period and mode changes request their documented combinations")
    func changesPeriodAndMode() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        await model.loadIfNeeded()

        await model.selectPeriod(.weekly)
        await model.selectPeriod(.monthly)
        await model.selectPeriod(.global)
        await model.selectMode(.extreme)

        #expect(fake.calls == [
            .init(period: .today, mode: .normal),
            .init(period: .weekly, mode: .normal),
            .init(period: .monthly, mode: .normal),
            .init(period: .global, mode: .normal),
            .init(period: .global, mode: .extreme),
        ])
    }

    @Test("Extreme takes the player's rank from its own board, not the mode-less rank lookup")
    func extremeRankComesFromBoard() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.selectPeriod(.global)
        #expect(model.currentUserRank == 13)

        await model.selectMode(.extreme)

        #expect(model.ranks?.globalRank == 13)
        #expect(model.currentUserRank == 3)
    }

    @Test("Extreme shows no rank when the player isn't on its board")
    func extremeRankHiddenOffBoard() async {
        let fake = FakeBandleLeaderboardService()
        fake.userId = "player-off-board"
        let model = BandleLeaderboardViewModel(service: fake.service)
        await model.loadIfNeeded()
        await model.selectPeriod(.global)
        #expect(model.currentUserRank == 13)

        await model.selectMode(.extreme)

        #expect(model.currentUserRank == nil)
    }

    @Test("Guests load public leaderboards without a rank request")
    func guestHasNoRanks() async {
        let fake = FakeBandleLeaderboardService()
        fake.userId = nil
        fake.isSignedIn = false
        let model = BandleLeaderboardViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.leaderboard?.entries?.isEmpty == false)
        #expect(model.ranks == nil)
        #expect(fake.rankCalls.isEmpty)
    }

    @Test("A failed period refresh explains the failure and keeps the selection")
    func reportsFailure() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        fake.shouldFail = true

        await model.selectPeriod(.monthly)

        #expect(model.period == .monthly)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("A failed period change doesn't show the previous period's board under the new title")
    func failedPeriodDropsStaleBoard() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        await model.loadIfNeeded()
        #expect(model.leaderboard != nil)
        fake.shouldFail = true

        await model.selectPeriod(.weekly)

        #expect(model.period == .weekly)
        #expect(model.leaderboard == nil)
        #expect(model.errorMessage != nil)
    }

    @Test("A failed mode change doesn't keep the other mode's statistics")
    func failedModeDropsStaleData() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        await model.loadIfNeeded()
        fake.shouldFail = true
        fake.shouldFailUserData = true

        await model.selectMode(.extreme)

        #expect(model.mode == .extreme)
        #expect(model.leaderboard == nil)
        #expect(model.userData == nil)
        #expect(model.history.isEmpty)
        #expect(model.ranks == nil)
        #expect(model.errorMessage != nil)
    }

    @Test("A failed rank lookup still shows the leaderboard")
    func rankFailureKeepsLeaderboard() async {
        let fake = FakeBandleLeaderboardService()
        fake.shouldFailRanks = true
        let model = BandleLeaderboardViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.leaderboard?.entries?.isEmpty == false)
        #expect(model.userData != nil)
        #expect(model.ranks == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("Guests never look up ranks, even when the server returns an id")
    func guestIdIsNotRanked() async {
        let fake = FakeBandleLeaderboardService()
        fake.userId = "guest-3f2a"
        fake.isSignedIn = false
        let model = BandleLeaderboardViewModel(service: fake.service)

        await model.loadIfNeeded()

        #expect(model.ranks == nil)
        #expect(fake.rankCalls.isEmpty)
    }

    @Test("A first load cancelled with the screen loads again when it returns")
    func cancelledFirstLoadLoadsAgain() async {
        let fake = FakeBandleLeaderboardService()
        let model = BandleLeaderboardViewModel(service: fake.service)
        let load = Task { await model.loadIfNeeded() }
        load.cancel()
        await load.value
        #expect(model.leaderboard == nil)

        await model.loadIfNeeded()

        #expect(model.leaderboard != nil)
    }
}
