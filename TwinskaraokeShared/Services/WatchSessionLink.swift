import Foundation

/// Vocabulary shared by the iPhone and Watch halves of the session bridge.
///
/// The watch cannot sign in on its own: no camera for the QR flow the TV uses,
/// no practical keyboard for a password. So the phone owns the session and the
/// watch mirrors it over WatchConnectivity.
///
/// The bearer token is deliberately *not* part of the application context. A
/// context is persisted by the system on both ends and replayed at launch, so a
/// token placed there would sit at rest in two app containers indefinitely. The
/// context carries only the non-secret `Descriptor` below; the watch pulls the
/// token itself with a transient `sendMessage` reply and writes it straight into
/// its own Keychain via `CredentialStore`.
///
/// Foundation only — this file also compiles into the tvOS target, which has no
/// WatchConnectivity. Both platform halves live in their own app target.
nonisolated enum WatchSessionLink {
    /// Posted on the phone whenever the persisted session changes, so the
    /// bridge can republish. `AuthManager` is minted fresh per `AccountView`
    /// visit, so the bridge cannot simply observe one instance.
    static let sessionChanged = Notification.Name("KaraokeWatchSessionChanged")

    /// Keys for the application context (phone → watch, latest-state-wins).
    enum ContextKey {
        static let generation = "nk.generation"
        static let isSignedIn = "nk.isSignedIn"
        static let userID = "nk.userId"
        static let username = "nk.username"
        static let avatar = "nk.avatar"
    }

    /// Keys for the interactive message (watch → phone, transient).
    enum MessageKey {
        static let kind = "nk.kind"
        static let token = "nk.token"
        static let isSignedIn = "nk.isSignedIn"
    }

    enum MessageKind {
        static let fetchToken = "fetchToken"
    }

    /// The non-secret half of a session: enough for the watch to render an
    /// account screen and to decide whether it needs to pull a token.
    struct Descriptor: Equatable, Sendable {
        var isSignedIn: Bool
        var userID: String?
        var username: String?
        var avatar: String?
        /// Bumped by the phone on every session change. The watch compares it
        /// against the generation it last applied so a context replayed at
        /// launch doesn't trigger a redundant token pull, while a sign-out and
        /// sign-in as the same user still does.
        var generation: Int

        static let signedOut = Descriptor(isSignedIn: false, generation: 0)
    }

    static func encode(_ descriptor: Descriptor) -> [String: Any] {
        var payload: [String: Any] = [
            ContextKey.isSignedIn: descriptor.isSignedIn,
            ContextKey.generation: descriptor.generation,
        ]
        // Identity fields are omitted rather than sent as NSNull: the context
        // dictionary only accepts property-list types.
        if let userID = descriptor.userID { payload[ContextKey.userID] = userID }
        if let username = descriptor.username { payload[ContextKey.username] = username }
        if let avatar = descriptor.avatar { payload[ContextKey.avatar] = avatar }
        return payload
    }

    /// Returns `nil` for a context that isn't ours, so an unrelated payload is
    /// ignored instead of being read as a sign-out.
    static func decode(_ payload: [String: Any]) -> Descriptor? {
        guard let isSignedIn = payload[ContextKey.isSignedIn] as? Bool else { return nil }
        return Descriptor(
            isSignedIn: isSignedIn,
            userID: payload[ContextKey.userID] as? String,
            username: payload[ContextKey.username] as? String,
            avatar: payload[ContextKey.avatar] as? String,
            generation: payload[ContextKey.generation] as? Int ?? 0
        )
    }
}
