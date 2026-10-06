import Foundation
import WatchConnectivity
import Observation

/// Watch half of the session bridge (see `WatchSessionLink`).
///
/// The watch never authenticates by itself. It mirrors whatever session the
/// phone reports: identity arrives in the application context, and the bearer
/// token is pulled separately and kept only in this device's Keychain, where
/// `KaraokeAPIClient` picks it up for every request.
@MainActor
@Observable
final class WatchAuthManager: NSObject {
    static let shared = WatchAuthManager()

    /// How the watch describes its own link to the phone, so the account
    /// screen can distinguish "you aren't signed in" from "I can't reach your
    /// phone to finish signing you in".
    enum LinkState: Equatable {
        case signedOut
        case signedIn
        case awaitingPhone
    }

    private(set) var linkState: LinkState = .signedOut
    private(set) var username: String?
    private(set) var userID: String?
    private(set) var avatarURL: URL?
    private(set) var isSyncing = false
    private(set) var accountRevision = 0

    private enum Key {
        static let username = "nk.watch.username"
        static let userID = "nk.watch.userId"
        static let avatar = "nk.watch.avatar"
        static let generation = "nk.watch.appliedGeneration"
    }

    private let defaults = UserDefaults.standard
    /// Set while a descriptor says we are signed in but no token has landed
    /// yet, so reachability changes know there is work to retry.
    private var favoritesObserver: NSObjectProtocol?
    private var expiredSessionObserver: NSObjectProtocol?
    private var rejectedToken: String?
    private var needsToken = false
    private var tokenRequestID: UUID?
    private var accountRequestID: UUID?
    private var lease = CompanionPlayback.readLease()
    private(set) var changingOutput = false
    var output: CompanionPlayback.Owner { lease?.owner ?? .phone }
    private var relinquishedLease = CompanionPlayback.decode(CompanionPlayback.Lease.self,
        from: UserDefaults.standard.data(forKey: "nk.watch.relinquishedLease"))
    var canPlayLocally: Bool { lease?.allowsAudio(on: .watch, relinquished: relinquishedLease) == true && !changingOutput }
    private var localPublishTask: Task<Void, Never>?
    private var lastPositionPublish = Date.distantPast
    private var commandGate = CompanionPlayback.CommandGate()
    private var applyingRemoteCommand = false
    private var lastLocalPlaybackChange = Date.distantPast
    private var playbackSnapshot: CompanionPlayback.Snapshot?
    private let playbackClientID = UUID()
    private var playbackSequence = 0

    nonisolated static func playbackMessageError(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == WCErrorDomain, error.code == WCError.Code.payloadTooLarge.rawValue {
            return "This playlist is too large to send. Open it on iPhone and control playback here."
        }
        return "Couldn't update iPhone playback. Open the iPhone app and try again."
    }

    var currentPlaybackSessionID: UUID? { playbackSnapshot?.sessionID }
    var currentPlaybackSongID: String? { playbackSnapshot?.song?.id }

    override private init() {
        super.init()
        restoreCachedIdentity()
    }

    /// Safe to call more than once; only the first call takes effect.
    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        if output == .watch, var saved = CompanionPlayback.decode(
            CompanionPlayback.Snapshot.self, from: defaults.data(forKey: "nk.watch.localPlayback")
        ), lease?.accepts(saved) == true {
            saved.isPlaying = false
            playbackSnapshot = saved
            AudioManager.shared.applyCompanionSnapshot(saved)
        }
        expiredSessionObserver = NotificationCenter.default.addObserver(forName: .karaokeSessionExpired,
            object: nil, queue: .main) { @Sendable [weak self] note in
            let expiredToken = note.userInfo?["requestToken"] as? String
            Task { @MainActor [weak self] in
                guard let self, let token = CredentialStore.token, token == expiredToken,
                      self.linkState == .signedIn else { return }
                self.rejectedToken = token
                CredentialStore.deleteToken()
                FavoritesManager.shared.clear()
                self.linkState = .awaitingPhone
                self.accountRevision &+= 1
                Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
                self.syncNow()
            }
        }
        favoritesObserver = NotificationCenter.default.addObserver(forName: FavoritesManager.didSave,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let userID = self.userID, self.linkState == .signedIn,
                      WCSession.default.isReachable else { return }
                WCSession.default.sendMessage([
                    WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.favoritesChanged,
                    WatchSessionLink.ContextKey.userID: userID], replyHandler: nil)
            }
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the phone using its current credentials when reachable. Independent
    /// watch networking remains available when the phone is out of range.
    func fetchPersonalPlaylists() async throws -> [Playlist]? {
        let session = WCSession.default
        guard linkState == .signedIn, session.activationState == .activated, session.isReachable else { return nil }
        let generation = defaults.integer(forKey: Key.generation)
        let identity = userID
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            session.sendMessage([WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.fetchPlaylists,
                "generation": generation, "userID": identity ?? ""], replyHandler: { @Sendable reply in
                if let data = reply["playlists"] as? Data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: KaraokeAPIClient.APIError.invalidResponse) }
            }, errorHandler: { @Sendable error in continuation.resume(throwing: error) })
        }
        guard userID == identity, linkState == .signedIn,
              defaults.integer(forKey: Key.generation) == generation else { throw CancellationError() }
        guard let playlists = CompanionPlayback.decode([UserPlaylist].self, from: data) else {
            throw KaraokeAPIClient.APIError.decodeFailed
        }
        return playlists.map { $0.asPlaylist() }
    }

    /// Manual retry for the account screen, for when the phone was out of
    /// range while a session change came through.
    func syncNow() {
        needsToken = true
        tokenRequestID = nil
        isSyncing = false
        requestAccountDescriptor()
        requestToken()
    }

    func refreshAccount() {
        Task { await FavoritesManager.shared.refreshFromCompanion() }
        requestAccountDescriptor()
        requestToken()
    }

    /// Pull the latest account identity after activation or reconnection. The
    /// application context normally delivers it, but an immediate pull closes
    /// the gap when the watch missed a sign-out or account switch offline.
    private func requestAccountDescriptor() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        let requestID = UUID()
        accountRequestID = requestID
        // WCSession invokes these callbacks on its own queue. Explicit
        // @Sendable prevents them inheriting this class's MainActor isolation;
        // a Task inside an actor-isolated callback would be too late to avoid
        // the runtime actor check at callback entry.
        session.sendMessage(
            [WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.fetchAccount],
            replyHandler: { @Sendable [weak self] response in
                let descriptor = WatchSessionLink.decode(response)
                let unavailable = response[WatchSessionLink.MessageKey.credentialUnavailable] as? Bool == true
                Task { @MainActor [weak self] in
                    guard let self, self.accountRequestID == requestID else { return }
                    self.accountRequestID = nil
                    if let descriptor { self.apply(descriptor) }
                    else if unavailable, self.linkState != .signedIn { self.linkState = .awaitingPhone }
                }
            },
            errorHandler: { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.accountRequestID == requestID else { return }
                    self?.accountRequestID = nil
                }
            }
        )
    }

    func selectOutput(_ owner: CompanionPlayback.Owner) {
        guard owner != output, !changingOutput else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            AudioManager.shared.playbackError = String(localized: "Connect your iPhone to change output. Choose Apple Watch before leaving your phone; downloaded songs then play offline.")
            return
        }
        if output == .watch {
            // Persist the stop before requesting a phone grant. If its reply
            // is lost, relaunching must not resume the relinquished lease.
            relinquishedLease = lease
            defaults.set(CompanionPlayback.encode(lease), forKey: "nk.watch.relinquishedLease")
            AudioManager.shared.stopForOutputTransfer()
        }
        changingOutput = true
        sendPlaybackCommand(CompanionPlayback.Command(
            sessionID: currentPlaybackSessionID,
            action: owner == .watch ? .transferToWatch : .transferToPhone
        ))
    }

    func localPlaybackDidChange(periodic: Bool = false) {
        guard output == .watch, !changingOutput else { return }
        if !periodic, !applyingRemoteCommand { lastLocalPlaybackChange = Date() }
        if periodic {
            guard Date().timeIntervalSince(lastPositionPublish) >= 2 else { return }
            lastPositionPublish = Date()
        }
        guard localPublishTask == nil else { return }
        localPublishTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.localPublishTask = nil
            self.publishLocalPlayback()
        }
    }

    private func publishLocalPlayback() {
        guard let lease, lease.owner == .watch else { return }
        var snapshot = AudioManager.shared.localSnapshot(lease: lease, revision: (playbackSnapshot?.revision ?? 0) + 1)
        snapshot.accountGeneration = defaults.integer(forKey: Key.generation)
        playbackSnapshot = snapshot
        guard let data = CompanionPlayback.encode(snapshot) else { return }
        defaults.set(data, forKey: "nk.watch.localPlayback")
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable { session.sendMessage([CompanionPlayback.contextKey: data], replyHandler: nil) }
        try? session.updateApplicationContext([CompanionPlayback.contextKey: data])
    }

    private func handlePhoneCommand(_ command: CompanionPlayback.Command) -> [String: Any] {
        guard command.accountGeneration == defaults.integer(forKey: Key.generation) else {
            return [CompanionPlayback.errorKey: "Account changed. Wait for account sync and try again."]
        }
        guard canPlayLocally, let lease, command.ownershipEpoch == lease.epoch,
              command.sessionID == lease.sessionID else {
            return [CompanionPlayback.errorKey: "Apple Watch is no longer the audio output."]
        }
        if localPublishTask != nil { publishLocalPlayback() }
        let decision = commandGate.decide(command, sessionID: lease.sessionID,
                                          revision: playbackSnapshot?.revision ?? 0,
                                          lastPhoneChangeAt: lastLocalPlaybackChange)
        if decision == .accept {
            applyingRemoteCommand = true
            AudioManager.shared.applyRemoteCommand(command)
            applyingRemoteCommand = false
        }
        publishLocalPlayback()
        var reply: [String: Any] = [:]
        if let data = CompanionPlayback.encode(playbackSnapshot) { reply[CompanionPlayback.replyDataKey] = data }
        if decision == .stale { reply[CompanionPlayback.errorKey] = "Playback changed. Try again." }
        return reply
    }

    /// Commands for the phone never fall back to local audio on connection
    /// failure: only an acknowledged ownership grant permits watch playback.
    @discardableResult
    func sendPlaybackCommand(_ command: CompanionPlayback.Command) -> Bool {
        guard WCSession.isSupported() else {
            AudioManager.shared.playbackError = String(localized: "Connect an iPhone to play music.")
            changingOutput = false
            return true
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            AudioManager.shared.playbackError = String(localized: "Connecting to iPhone. Try again in a moment.")
            AudioManager.shared.isLoading = false
            changingOutput = false
            return true
        }
        guard session.isCompanionAppInstalled else {
            AudioManager.shared.playbackError = String(localized: "Install Twinskaraoke on your paired iPhone to play music.")
            AudioManager.shared.isLoading = false
            changingOutput = false
            return true
        }
        var command = command
        playbackSequence &+= 1
        command.clientID = playbackClientID
        command.sequence = playbackSequence
        command.baseRevision = playbackSnapshot?.revision
        command.ownershipEpoch = lease?.epoch
        command.accountGeneration = defaults.integer(forKey: Key.generation)
        let sentSequence = command.sequence
        guard session.isReachable,
              let data = CompanionPlayback.encode(command) else {
            AudioManager.shared.playbackError = String(localized: "iPhone is out of reach. Bring it nearby and try again.")
            AudioManager.shared.isLoading = false
            changingOutput = false
            return true
        }
        session.sendMessage(
            [WatchSessionLink.MessageKey.kind: CompanionPlayback.messageKind,
             CompanionPlayback.messageDataKey: data],
            replyHandler: { @Sendable [weak self] reply in
                let snapshot = CompanionPlayback.decode(
                    CompanionPlayback.Snapshot.self,
                    from: reply[CompanionPlayback.replyDataKey] as? Data
                )
                let error = reply[CompanionPlayback.errorKey] as? String
                Task { @MainActor [weak self] in
                    self?.changingOutput = false
                    if let snapshot { self?.applyPlayback(snapshot) }
                    guard self?.playbackSequence == sentSequence else { return }
                    if let error {
                        AudioManager.shared.playbackError = error
                    } else if snapshot == nil {
                        if let previous = self?.playbackSnapshot {
                            AudioManager.shared.applyCompanionSnapshot(previous)
                        }
                        AudioManager.shared.playbackError = String(localized: "iPhone couldn't update playback. Try again.")
                    }
                    AudioManager.shared.isLoading = false
                }
            },
            errorHandler: { @Sendable [weak self] error in
                let message = Self.playbackMessageError(error)
                Task { @MainActor [weak self] in
                    guard self?.playbackSequence == sentSequence else { return }
                    self?.changingOutput = false
                    if let snapshot = self?.playbackSnapshot {
                        AudioManager.shared.applyCompanionSnapshot(snapshot)
                    }
                    AudioManager.shared.playbackError = message
                    AudioManager.shared.isLoading = false
                }
            }
        )
        return true
    }

    private func applyPlayback(_ snapshot: CompanionPlayback.Snapshot) {
        guard snapshot.accountGeneration == defaults.integer(forKey: Key.generation) else { return }
        if let lease, lease.sessionID == snapshot.sessionID {
            guard snapshot.ownershipEpoch >= lease.epoch else { return }
            // The phone only echoes watch-owned state. The running watch is
            // authoritative within its grant, including while disconnected.
            if lease.owner == .watch, snapshot.ownershipEpoch == lease.epoch { return }
        }
        guard snapshot.supersedes(playbackSnapshot) else { return }
        let nextLease = CompanionPlayback.Lease(sessionID: snapshot.sessionID,
                                               owner: snapshot.owner, epoch: snapshot.ownershipEpoch)
        lease = nextLease
        CompanionPlayback.saveLease(nextLease)
        playbackSnapshot = snapshot
        AudioManager.shared.applyCompanionSnapshot(snapshot)
        if snapshot.owner == .watch { publishLocalPlayback() }
    }

    // MARK: - State

    private func restoreCachedIdentity() {
        username = defaults.string(forKey: Key.username)
        userID = defaults.string(forKey: Key.userID)
        avatarURL = defaults.string(forKey: Key.avatar).flatMap(URL.init(string:))
        // The Keychain is the record of being signed in; the cached identity is
        // only what we draw with. A username without a token means the token
        // pull never completed.
        if CredentialStore.token != nil {
            linkState = .signedIn
        } else {
            linkState = username == nil ? .signedOut : .awaitingPhone
            needsToken = username != nil
        }
    }

    private func apply(_ descriptor: WatchSessionLink.Descriptor) {
        let appliedGeneration = defaults.integer(forKey: Key.generation)
        guard descriptor.mayReplace(appliedGeneration: appliedGeneration) else { return }
        guard descriptor.isSignedIn else {
            // Playback snapshots reuse the latest application context. A
            // guest session can therefore deliver this same descriptor every
            // few seconds; clearing the cache each time races playback and
            // forces every account-scoped screen to reload unnecessarily.
            if linkState != .signedOut || userID != nil || CredentialStore.token != nil {
                clearSession()
            }
            defaults.set(descriptor.generation, forKey: Key.generation)
            return
        }

        if descriptor.generation == appliedGeneration,
           descriptor.userID == userID,
           descriptor.username == username,
           descriptor.avatar.flatMap(URL.init(string:)) == avatarURL,
           CredentialStore.token != nil {
            return
        }

        let identityChanged = descriptor.userID != userID
        // A context is replayed on every activation, so only pull a token when
        // this is genuinely new state or we never got one.
        //
        // `identityChanged` has to count even when the generation matches: the
        // phone only bumps it when it can reach a paired watch, so signing out
        // and back in as someone else while unpaired lands here with the old
        // generation. Without this the token below would be dropped and never
        // replaced, leaving the watch signed in with no credentials.
        let needsFreshToken = descriptor.generation != appliedGeneration
            || identityChanged
            || CredentialStore.token == nil

        if identityChanged {
            AudioManager.shared.clearAccountPlayback()
            WatchDownloads.shared.removeAll()
        }
        if needsFreshToken, CredentialStore.token != nil {
            // Different account than the one cached: drop the old token rather
            // than leaving it usable until the new one arrives.
            CredentialStore.deleteToken()
            FavoritesManager.shared.clear()
            RecentlyPlayedStore.shared.clear()
            AudioManager.shared.clearCache()
            Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
        }

        username = descriptor.username
        userID = descriptor.userID
        avatarURL = descriptor.avatar.flatMap(URL.init(string:))
        defaults.set(descriptor.username, forKey: Key.username)
        defaults.set(descriptor.userID, forKey: Key.userID)
        defaults.set(descriptor.avatar, forKey: Key.avatar)
        defaults.set(descriptor.generation, forKey: Key.generation)

        if needsFreshToken {
            // A reply to an older account/generation must not leave the new
            // pull blocked behind its stale `isSyncing` flag.
            tokenRequestID = nil
            isSyncing = false
            needsToken = true
            linkState = .awaitingPhone
            requestToken()
        } else {
            linkState = .signedIn
        }
    }

    private func clearSession() {
        rejectedToken = nil
        AudioManager.shared.clearAccountPlayback()
        WatchDownloads.shared.removeAll()
        tokenRequestID = nil
        CredentialStore.deleteToken()
        // Anything fetched while signed in was scoped to that account.
        FavoritesManager.shared.clear()
        RecentlyPlayedStore.shared.clear()
        AudioManager.shared.clearCache()
        Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
        needsToken = false
        isSyncing = false
        username = nil
        userID = nil
        avatarURL = nil
        linkState = .signedOut
        [Key.username, Key.userID, Key.avatar].forEach(defaults.removeObject(forKey:))
    }

    // MARK: - Token pull

    private func requestToken() {
        guard needsToken, !isSyncing else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Out of range: `sessionReachabilityDidChange` retries.
        guard session.isReachable else { return }

        isSyncing = true
        let requestID = UUID()
        tokenRequestID = requestID
        let generation = defaults.integer(forKey: Key.generation)
        session.sendMessage(
            [WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.fetchToken,
             "generation": generation, "userID": userID ?? ""],
            replyHandler: { @Sendable [weak self] reply in
                let result = WatchSessionLink.decodeTokenReply(reply)
                let descriptor = WatchSessionLink.decode(reply)
                Task { @MainActor [weak self] in
                    guard let self, WatchSessionLink.acceptsTokenReply(
                        requestID: requestID, activeRequestID: self.tokenRequestID,
                        requestGeneration: generation,
                        appliedGeneration: self.defaults.integer(forKey: Key.generation)
                    ) else { return }
                    if let descriptor, descriptor.generation != generation || descriptor.userID != self.userID || !descriptor.isSignedIn {
                        self.isSyncing = false
                        self.tokenRequestID = nil
                        self.apply(descriptor)
                        return
                    }
                    switch result {
                    case .available(let token): self.receive(token: token, signedIn: true)
                    case .signedOut: self.receive(token: nil, signedIn: false)
                    case .unavailable: self.isSyncing = false
                    }
                }
            },
            errorHandler: { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.tokenRequestID == requestID else { return }
                    // Leave `needsToken` set so the next reachability change or
                    // manual sync tries again.
                    self?.isSyncing = false
                }
            }
        )
    }

    private func receive(token: String?, signedIn: Bool) {
        isSyncing = false
        tokenRequestID = nil
        guard signedIn, let token, !token.isEmpty else {
            // The phone signed out between publishing the context and our pull.
            clearSession()
            return
        }
        guard token != rejectedToken else {
            needsToken = true
            linkState = .awaitingPhone
            return
        }
        do {
            try CredentialStore.saveToken(token)
            rejectedToken = nil
            // Whatever was fetched as a guest is now the wrong scope.
            Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
            // Star state is account-scoped and now fetchable for the first time.
            FavoritesManager.shared.reload()
            needsToken = false
            linkState = .signedIn
            accountRevision &+= 1
        } catch {
            linkState = .awaitingPhone
        }
    }
}

extension WatchAuthManager: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {
        Task { @MainActor [weak self] in
            if let context = WCSession.isSupported() ? WCSession.default.receivedApplicationContext : nil {
                if let descriptor = WatchSessionLink.decode(context) { self?.apply(descriptor) }
                if let snapshot = CompanionPlayback.decode(
                    CompanionPlayback.Snapshot.self,
                    from: context[CompanionPlayback.contextKey] as? Data
                ) { self?.applyPlayback(snapshot) }
            }
            self?.requestAccountDescriptor()
            self?.requestToken()
            self?.publishLocalPlayback()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in
            await FavoritesManager.shared.refreshFromCompanion()
            self?.requestAccountDescriptor()
            self?.requestToken()
            self?.publishLocalPlayback()
            if let self, self.output == .watch, !self.canPlayLocally { self.selectOutput(.phone) }
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
        // Decoded here, off the main actor, because `[String: Any]` cannot
        // cross actors but `Descriptor` can.
        let descriptor = WatchSessionLink.decode(context)
        let snapshot = CompanionPlayback.decode(
            CompanionPlayback.Snapshot.self,
            from: context[CompanionPlayback.contextKey] as? Data
        )
        Task { @MainActor [weak self] in
            if let descriptor { self?.apply(descriptor) }
            if let snapshot { self?.applyPlayback(snapshot) }
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if message[WatchSessionLink.MessageKey.kind] as? String == WatchSessionLink.MessageKind.favoritesChanged {
            let userID = message[WatchSessionLink.ContextKey.userID] as? String
            Task { @MainActor [weak self] in
                guard let self, self.linkState == .signedIn, userID != nil, self.userID == userID else { return }
                await FavoritesManager.shared.refreshFromCompanion()
            }
            return
        }
        guard let snapshot = CompanionPlayback.decode(
            CompanionPlayback.Snapshot.self,
            from: message[CompanionPlayback.contextKey] as? Data
        ) else { return }
        Task { @MainActor [weak self] in self?.applyPlayback(snapshot) }
    }
    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = CompanionPlayback.decode(CompanionPlayback.Command.self,
            from: message[CompanionPlayback.messageDataKey] as? Data) else {
            replyHandler([:]); return
        }
        let reply = WatchPlaybackReply(replyHandler)
        Task { @MainActor [weak self] in reply.send(self?.handlePhoneCommand(command) ?? [:]) }
    }

}

private nonisolated final class WatchPlaybackReply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
    init(_ send: @escaping ([String: Any]) -> Void) { self.send = send }
}
