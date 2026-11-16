import Foundation
import Observation

@MainActor
@Observable
final class BandleLeaderboardViewModel {
    private(set) var mode: BandleMode = .normal
    private(set) var period: BandleLeaderboardPeriod = .today
    private(set) var leaderboard: BandleLeaderboard?
    private(set) var userData: BandleUserData?
    private(set) var history: [BandleHistoryEntry] = []
    private(set) var globalStats: BandleGlobalStats?
    private(set) var ranks: BandleUserRanks?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: Service
    @ObservationIgnored private var hasLoaded = false
    /// The signed-in player's id; guests have none.
    private var rankedUserId: String?

    init(service: Service = AppRuntime.isUITestMode ? .uiTestFixture : .live) {
        self.service = service
    }

    var currentUserRank: Int? {
        // The ranks endpoint takes no mode, so like the leaderboards'
        // default it describes Normal. Other modes use the player's entry on
        // the loaded board, if they're on it.
        if mode == .normal, let rank = ranks?[keyPath: period.rankKeyPath] {
            return rank
        }
        guard let rankedUserId else { return nil }
        return leaderboard?.entries?.first { $0.userId == rankedUserId }?.rank
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
        // Cancelled with the screen: load again when it next appears.
        if Task.isCancelled {
            hasLoaded = false
        }
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let boardRequest = service.leaderboard(period, mode)
            async let userRequest = service.userData(mode)
            async let historyRequest = service.history(mode)
            async let globalRequest = service.globalStats()
            async let statusRequest = service.playStatus(mode)
            leaderboard = try await boardRequest
            userData = try await userRequest
            history = try await historyRequest
            globalStats = try await globalRequest
            let status = try await statusRequest
            rankedUserId = service.isSignedIn() ? status.userId : nil
            ranks = await loadRanks(userId: rankedUserId)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "Couldn't load Bandle statistics. Check your connection and try again.")
        }
    }

    func selectPeriod(_ newPeriod: BandleLeaderboardPeriod) async {
        guard newPeriod != period, !isLoading else { return }
        period = newPeriod
        // The previous period's board must not stay on screen under the new
        // title if this request fails.
        leaderboard = nil
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leaderboard = try await service.leaderboard(period, mode)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "Couldn't load this Bandle leaderboard. Please try again.")
        }
    }

    func selectMode(_ newMode: BandleMode) async {
        guard newMode != mode, !isLoading else { return }
        mode = newMode
        // Everything below belongs to one mode; a failed reload must not leave
        // the other mode's numbers under the new selection.
        leaderboard = nil
        userData = nil
        history = []
        ranks = nil
        await reload()
    }

    /// A rank is extra; failing to load it doesn't hide the leaderboard.
    private func loadRanks(userId: String?) async -> BandleUserRanks? {
        guard let userId, !userId.isEmpty else { return nil }
        do {
            return try await service.ranks(userId)
        } catch {
            DebugLogger.log("Bandle rank lookup failed: \(error)", category: .network)
            return nil
        }
    }
}
