import Foundation

enum UserSessionScope: Equatable, Sendable {
    case authenticated(token: String)
    case guest(id: String)

    static var current: UserSessionScope {
        if let token = UserDefaults.standard.string(forKey: "nk.token"), !token.isEmpty {
            return .authenticated(token: token)
        }
        return .guest(id: GuestIdentity.current)
    }

    nonisolated var authenticationToken: String? {
        guard case let .authenticated(token) = self else { return nil }
        return token
    }

    nonisolated var guestID: String? {
        guard case let .guest(id) = self else { return nil }
        return id
    }
}
