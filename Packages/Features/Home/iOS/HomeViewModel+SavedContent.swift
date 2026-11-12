import Foundation

/// Whose Home is showing. "Made for You" is saved and shown per account.
nonisolated enum HomeAccount: Equatable, Sendable {
    case signedOut
    case signedIn(String)

    /// Nil when the account can't be told: the Keychain is locked, or a
    /// signed-in session has no user ID or name.
    init?(_ descriptor: WatchSessionLink.Descriptor?) {
        guard let descriptor else { return nil }
        guard descriptor.isSignedIn else {
            self = .signedOut
            return
        }
        guard let identity = descriptor.userID ?? descriptor.username, !identity.isEmpty else { return nil }
        self = .signedIn(identity)
    }

    /// The key "Made for You" is saved under; nil when signed out.
    var suggestionsKey: String? {
        guard case let .signedIn(identity) = self else { return nil }
        return identity
    }
}

extension HomeViewModel {
    /// The signed-in account as storage records it. Read off the main actor:
    /// it reads the Keychain.
    nonisolated static let liveAccountIdentity: @Sendable () async -> HomeAccount? = {
        await Task.detached(priority: .userInitiated) {
            HomeAccount(AuthManager.persistedDescriptor())
        }.value
    }

    /// The shelves a load got back with something in them, to merge into the
    /// saved copy. A shelf whose request failed or came back empty is left
    /// out, so the copy already saved for it stays.
    nonisolated static func freshSnapshot(
        trending: [Song]?,
        releases: [Song]?,
        topPicks: [Playlist]?,
        topPicksSource: HomeTopPicksSource
    ) -> HomeFeedSnapshot {
        let topPicks = topPicks?.isEmpty == false ? topPicks : nil
        return HomeFeedSnapshot(
            trending: trending?.isEmpty == false ? trending : nil,
            newReleases: releases?.isEmpty == false ? releases : nil,
            topPicks: topPicks,
            topPicksSource: topPicks == nil ? nil : topPicksSource
        )
    }
}
