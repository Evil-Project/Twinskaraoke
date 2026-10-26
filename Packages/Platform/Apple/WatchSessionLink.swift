import Foundation
nonisolated enum WatchSessionLink {
    static let sessionChanged = Notification.Name("KaraokeWatchSessionChanged")
    enum ContextKey {
        static let generation = "nk.generation"
        static let phoneInstanceID = "nk.phoneInstanceID"
        static let isSignedIn = "nk.isSignedIn"
        static let userID = "nk.userId"
        static let username = "nk.username"
        static let avatar = "nk.avatar"
    }
    enum MessageKey {
        static let kind = "nk.kind"
        static let token = "nk.token"
        static let isSignedIn = "nk.isSignedIn"
        static let credentialUnavailable = "nk.credentialUnavailable"
    }

    enum MessageKind {
        static let fetchToken = "fetchToken"
        static let fetchPlaylists = "fetchPlaylists"
        static let fetchAccount = "fetchAccount"
        static let favoritesChanged = "favoritesChanged"
    }

    enum TokenReply: Equatable, Sendable {
        case available(String)
        case signedOut
        case unavailable
    }

    static func tokenReply(for result: CredentialStore.TokenReadResult) -> [String: Any] {
        switch result {
        case .available(let token):
            return [MessageKey.isSignedIn: true, MessageKey.token: token]
        case .missing:
            return [MessageKey.isSignedIn: false]
        case .unavailable:
            return [MessageKey.credentialUnavailable: true]
        }
    }

    static func decodeTokenReply(_ payload: [String: Any]) -> TokenReply {
        if payload[MessageKey.credentialUnavailable] as? Bool == true { return .unavailable }
        guard let signedIn = payload[MessageKey.isSignedIn] as? Bool else { return .unavailable }
        if !signedIn { return .signedOut }
        guard let token = payload[MessageKey.token] as? String, !token.isEmpty else { return .unavailable }
        return .available(token)
    }

    static func tokenRequestMatches(
        generation: Int?, userID: String?,
        descriptor: Descriptor, currentGeneration: Int, phoneInstanceID: String? = nil
    ) -> Bool {
        descriptor.isSignedIn && generation == currentGeneration && userID == descriptor.userID
            && phoneInstanceID == descriptor.phoneInstanceID
    }

    static func acceptsTokenReply(
        requestID: UUID,
        activeRequestID: UUID?,
        requestGeneration: Int,
        appliedGeneration: Int
    ) -> Bool {
        requestID == activeRequestID && requestGeneration == appliedGeneration
    }

    typealias Descriptor = AccountSessionDescriptor

    static func encode(_ descriptor: Descriptor) -> [String: Any] {
        var payload: [String: Any] = [
            ContextKey.isSignedIn: descriptor.isSignedIn,
            ContextKey.generation: descriptor.generation,
        ]
        if let userID = descriptor.userID { payload[ContextKey.userID] = userID }
        if let username = descriptor.username { payload[ContextKey.username] = username }
        if let avatar = descriptor.avatar { payload[ContextKey.avatar] = avatar }
        if let id = descriptor.phoneInstanceID { payload[ContextKey.phoneInstanceID] = id }
        return payload
    }
    static func decode(_ payload: [String: Any]) -> Descriptor? {
        guard let isSignedIn = payload[ContextKey.isSignedIn] as? Bool else { return nil }
        return Descriptor(
            isSignedIn: isSignedIn,
            userID: payload[ContextKey.userID] as? String,
            username: payload[ContextKey.username] as? String,
            avatar: payload[ContextKey.avatar] as? String,
            generation: payload[ContextKey.generation] as? Int ?? 0,
            phoneInstanceID: payload[ContextKey.phoneInstanceID] as? String
        )
    }
}
