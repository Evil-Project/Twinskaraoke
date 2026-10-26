import Foundation

/// The non-secret half of a session: enough for the watch to render an
/// account screen and to decide whether it needs to pull a token.
nonisolated struct AccountSessionDescriptor: Equatable, Sendable {
    var isSignedIn: Bool
    var userID: String?
    var username: String?
    var avatar: String?
    var generation: Int
    /// Ordering is scoped to one phone installation, whose counter survives
    /// relaunch but can reset after reinstalling or restoring app data.
    var phoneInstanceID: String? = nil

    static let signedOut = AccountSessionDescriptor(isSignedIn: false, generation: 0)

    func mayReplace(appliedGeneration: Int, appliedInstanceID: String? = nil,
                    retiredInstanceIDs: Set<String> = []) -> Bool {
        if let phoneInstanceID, phoneInstanceID != appliedInstanceID {
            return !retiredInstanceIDs.contains(phoneInstanceID)
        }
        // Once upgraded, a delayed legacy context cannot reset ordering.
        guard phoneInstanceID == appliedInstanceID else { return false }
        return generation >= appliedGeneration
    }
}
