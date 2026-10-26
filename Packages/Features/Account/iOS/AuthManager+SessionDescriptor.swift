import Foundation

extension AuthManager {
    /// The committed account descriptor for history and companion adapters.
    ///
    /// Reads committed storage because Keychain is the authoritative token source.
    /// `generation` is filled in by the publisher.
    nonisolated static func persistedDescriptor() -> AccountSessionDescriptor? {
        let defaults = UserDefaults.standard
        let result = CredentialStore.readToken()
        guard case .unavailable = result else {
            return persistedDescriptor(token: result.token, defaults: defaults)
        }
        return nil
    }

    private nonisolated static func persistedDescriptor(token: String?, defaults: UserDefaults) -> AccountSessionDescriptor {
        let username = defaults.string(forKey: "nk.username")
        guard persistedSessionIsComplete(
            token: token,
            username: username,
            commitMarker: defaults.object(forKey: "nk.sessionCommitted") as? Bool
        ) else {
            return .signedOut
        }
        return AccountSessionDescriptor(
            isSignedIn: true,
            userID: defaults.string(forKey: "nk.userId"),
            username: username,
            avatar: defaults.string(forKey: "nk.avatar"),
            generation: 0
        )
    }

}
