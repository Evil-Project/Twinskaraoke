import Foundation

/// Every upload belongs to the account that started it. The request reads
/// whichever token is current when it is sent, so without this an upload
/// queued by one account could land in the next one's library.
extension SongUploadController {
    /// Whether `id` was started by an account other than `current`. An
    /// account that couldn't be told on either side counts as the same: the
    /// request then fails on its own if nobody is signed in.
    func belongsToAnotherAccount(_ id: UUID, current: String?) -> Bool {
        guard let started = records[id]?.account, let current else { return false }
        return started != current
    }

    /// Fails `id` as signed out when another account is signed in now, so
    /// nothing is sent for it. Returns whether it did.
    func refuseForAnotherAccount(_ id: UUID) -> Bool {
        guard belongsToAnotherAccount(id, current: service.currentAccount()) else { return false }
        DebugLogger.log("Upload not sent: another account is signed in", category: .network)
        fail(id, .signedOut)
        return true
    }

    /// After a sign-in, sign-out or account switch, the previous account's
    /// waiting and ended uploads leave the list with their staged bodies. One
    /// already running finishes under the token it was sent with (or is
    /// refused before it sends) and leaves the list when it ends.
    func accountMayHaveChanged() {
        let current = service.currentAccount()
        for item in uploads where belongsToAnotherAccount(item.id, current: current) {
            if item.phase == .waiting || !item.isActive {
                removeItem(item.id)
            } else {
                records[item.id]?.leavesListWhenEnded = true
            }
        }
    }
}
