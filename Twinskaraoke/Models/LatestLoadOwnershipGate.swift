import Foundation

nonisolated struct LatestLoadOwnershipGate: Sendable {
    struct Token: Sendable, Equatable {
        fileprivate let id: UUID
    }

    private(set) var activeToken: Token?

    mutating func begin() -> Token {
        let token = Token(id: UUID())
        activeToken = token
        return token
    }

    func owns(_ token: Token) -> Bool {
        activeToken == token
    }

    mutating func finish(_ token: Token) -> Bool {
        guard owns(token) else { return false }
        activeToken = nil
        return true
    }

    @discardableResult
    mutating func cancel() -> Token? {
        let cancelled = activeToken
        activeToken = nil
        return cancelled
    }
}
