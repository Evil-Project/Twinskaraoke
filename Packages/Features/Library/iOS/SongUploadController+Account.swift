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
    ///
    /// Unlike `belongsToAnotherAccount`, this fails closed: an upload whose
    /// account is known isn't sent while the current one can't be read (the
    /// Keychain is locked, say), since the token sent could be anyone's. It
    /// fails as interrupted, which the user can retry once it can be read.
    func refuseForAnotherAccount(_ id: UUID) -> Bool {
        let current = service.currentAccount()
        if records[id]?.source != nil, records[id]?.account == nil {
            refuseWithoutOwner(id)
            return true
        }
        if current == nil, records[id]?.account != nil {
            DebugLogger.log("Upload not sent: the signed-in account can't be read", category: .network)
            fail(id, .interrupted)
            return true
        }
        guard belongsToAnotherAccount(id, current: current) else { return false }
        DebugLogger.log("Upload not sent: another account is signed in", category: .network)
        fail(id, .signedOut)
        return true
    }

    /// An upload started while the signed-in account can't be read has no
    /// owner to check later, so it could go out under whichever token is
    /// current by then. It fails at once, before anything is staged or sent,
    /// as interrupted: the user can retry once the account can be read.
    func refuseWithoutOwner(_ id: UUID) {
        DebugLogger.log("Upload not queued: the signed-in account can't be read", category: .network)
        fail(id, .interrupted)
    }

    /// Before a retry: an upload started this launch without a readable
    /// account takes the one signed in now. Returns `false` when that still
    /// can't be read. An upload restored from an earlier build's outbox
    /// without an account keeps none, as before.
    func claimOwnerForRetry(_ id: UUID) -> Bool {
        guard let record = records[id], record.source != nil, record.account == nil else { return true }
        guard let current = service.currentAccount() else { return false }
        records[id]?.account = current
        return true
    }

    /// After a relaunch, an upload another account started is never listed:
    /// one still running finishes unseen, any other is dropped with its
    /// staged body. An account that can't be told on either side sets
    /// nothing aside. Returns whether `entry` was set aside.
    func setAsideForAnotherAccount(_ entry: PendingUpload, current: String?, running: Bool) -> Bool {
        guard let started = entry.account, let current, started != current else { return false }
        if running {
            records[entry.id] = Record(
                source: nil,
                key: "staged:\(entry.id)",
                staged: entry.staged(),
                taskID: entry.taskID,
                knownSongIDs: entry.knownSongIDs,
                account: started,
                endsUnseen: true
            )
        } else {
            service.discard(entry.staged())
            service.outbox.remove(id: entry.id)
        }
        DebugLogger.log("Upload of another account set aside after relaunch", category: .network)
        return true
    }

    /// The transfer of an upload set aside for another account ended: no
    /// banner, notification or retry, just its body and outbox entry gone.
    func endUnseen(_ id: UUID, taskID: Int) {
        if let staged = records.removeValue(forKey: id)?.staged {
            service.discard(staged)
            service.outbox.remove(id: staged.id)
        }
        service.transport.acknowledge(taskID)
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
