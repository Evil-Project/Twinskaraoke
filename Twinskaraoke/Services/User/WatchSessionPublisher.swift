import Foundation
import WatchConnectivity
import UIKit

private nonisolated final class WatchReplyBox: @unchecked Sendable {
    let send: ([String: Any]) -> Void
    init(_ send: @escaping ([String: Any]) -> Void) { self.send = send }
}

/// Phone half of the watch session bridge (see `WatchSessionLink`).
///
/// Publishes the non-secret session descriptor to the watch as an application
/// context, and answers the watch's transient request for the bearer token.
/// Activated once at launch and lives for the process: `AuthManager` instances
/// come and go with `AccountView`, so session changes arrive by notification.
@MainActor
final class WatchSessionPublisher: NSObject {
    static let shared = WatchSessionPublisher()

    private static let generationKey = "nk.watchSessionGeneration"
    private static let instanceKey = "nk.watchSessionInstance"
    private static let takeoverKey = "nk.phone.pendingTakeover"

    private var phoneInstanceID: String {
        if let saved = defaults.string(forKey: Self.instanceKey) { return saved }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.instanceKey)
        return id
    }

    private let defaults = UserDefaults.standard
    private var restorationObservers: [NSObjectProtocol] = []
    private var favoritesObserver: NSObjectProtocol?
    private var sessionChangedObserver: NSObjectProtocol?
    private var lease = CompanionPlayback.readLease() ?? CompanionPlayback.Lease()
    private var watchSnapshot: CompanionPlayback.Snapshot?
    private var pendingTakeover: CompanionPlayback.Lease?
    private let commandClientID = UUID()
    private var commandSequence = 0
    var watchOwnsAudio: Bool { lease.owner == .watch }
    private var playbackSessionID: UUID { lease.sessionID }
    private var playbackRevision = 0
    private var lastPlaybackFingerprint: Data?
    private var commandGate = CompanionPlayback.CommandGate()
    private var lastPhoneStructuralChangeAt = Date.distantPast
    private var isApplyingWatchCommand = false
    private var publishPlaybackTask: Task<Void, Never>?
    private var lastPeriodicPlaybackPublishAt = Date.distantPast

    override private init() {
        super.init()
        CompanionPlayback.saveLease(lease)
        playbackRevision = defaults.integer(forKey: "nk.phone.playbackRevision")
        watchSnapshot = CompanionPlayback.decode(CompanionPlayback.Snapshot.self,
                                                 from: defaults.data(forKey: "nk.phone.watchPlayback"))
        pendingTakeover = CompanionPlayback.decode(CompanionPlayback.Lease.self,
            from: defaults.data(forKey: Self.takeoverKey))
        if watchSnapshot?.belongsToAccount(generation: currentGeneration, phoneInstanceID: phoneInstanceID) != true {
            watchSnapshot = nil
            defaults.removeObject(forKey: "nk.phone.watchPlayback")
        }
    }

    /// Safe to call more than once; only the first call takes effect.
    func activate() {
        // False on iPad and any device that can't pair a watch.
        guard WCSession.isSupported() else { return }
        guard sessionChangedObserver == nil else { return }

        sessionChangedObserver = NotificationCenter.default.addObserver(
            forName: WatchSessionLink.sessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.publish(bumpingGeneration: true)
            }
        }

        restorationObservers = [UIApplication.didBecomeActiveNotification,
                                UIApplication.protectedDataDidBecomeAvailableNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publish(bumpingGeneration: false)
                    await FavoritesManager.shared.refreshFromCompanion()
                }
            }
        }
        favoritesObserver = NotificationCenter.default.addObserver(forName: FavoritesManager.didSave,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishFavoritesChange() }
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if watchOwnsAudio, let snapshot = watchSnapshot, lease.accepts(snapshot) {
            AudioPlayerManager.shared.applyWatchSnapshot(snapshot)
        }
    }

    private func publishFavoritesChange() {
        guard let account = AuthManager.persistedDescriptor(), account.isSignedIn,
              let userID = account.userID, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.favoritesChanged,
                                      WatchSessionLink.ContextKey.userID: userID], replyHandler: nil)
    }

    func playbackDidChange(periodic: Bool = false) {
        guard !watchOwnsAudio else { return }
        if periodic {
            let now = Date()
            guard now.timeIntervalSince(lastPeriodicPlaybackPublishAt) >= 2 else { return }
            lastPeriodicPlaybackPublishAt = now
        }
        publishPlaybackTask?.cancel()
        publishPlaybackTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.publishPlayback()
        }
    }

    private func playbackSnapshot() -> CompanionPlayback.Snapshot {
        if watchOwnsAudio {
            if let watchSnapshot, lease.accepts(watchSnapshot),
               watchSnapshot.belongsToAccount(generation: currentGeneration, phoneInstanceID: phoneInstanceID) {
                return watchSnapshot
            }
            // Missing local presentation data does not revoke the watch's
            // persisted grant or create a second audio owner.
            return CompanionPlayback.Snapshot(sessionID: lease.sessionID, revision: 0, owner: .watch,
                song: nil, queue: [], isPlaying: false, isRadio: false, radioArtworkURL: nil,
                position: 0, duration: 0, isShuffled: false, repeatSetting: .off,
                error: nil, updatedAt: .distantPast, ownershipEpoch: lease.epoch,
                accountGeneration: currentGeneration, phoneInstanceID: phoneInstanceID)
        }
        let player = AudioPlayerManager.shared
        let song = player.currentSong
        // Elapsed time does not create a new revision on every poll tick.
        let fingerprint = CompanionPlayback.encode(PlaybackFingerprint(
            song: song, queue: player.queue,
            isPlaying: player.isPlaying, isRadio: player.isRadioMode,
            isShuffled: player.isShuffled, repeatSetting: repeatSetting(player.repeatMode),
            error: player.loadFailure?.message, sleepDeadline: player.sleepTimer.deadline,
            sleepAtEndOfSong: player.sleepTimer.endsWithCurrentSong
        ))
        if fingerprint != lastPlaybackFingerprint {
            playbackRevision &+= 1
            defaults.set(playbackRevision, forKey: "nk.phone.playbackRevision")
            lastPlaybackFingerprint = fingerprint
            if !isApplyingWatchCommand { lastPhoneStructuralChangeAt = Date() }
        }
        let snapshot = CompanionPlayback.Snapshot(
            sessionID: playbackSessionID, revision: playbackRevision, owner: .phone,
            song: song, queue: player.queue, isPlaying: player.isPlaying,
            isRadio: player.isRadioMode, radioArtworkURL: player.radioArtworkURL,
            position: player.playbackTime,
            duration: player.playbackDuration, isShuffled: player.isShuffled,
            repeatSetting: repeatSetting(player.repeatMode), error: player.loadFailure?.message,
            updatedAt: Date(), ownershipEpoch: lease.epoch, radioStreamURL: player.radioStreamURL,
            accountGeneration: currentGeneration, phoneInstanceID: phoneInstanceID, sleepDeadline: player.sleepTimer.deadline,
            sleepAtEndOfSong: player.sleepTimer.endsWithCurrentSong
        )
        return snapshot
    }

    private struct PlaybackFingerprint: Encodable {
        let song: Song?
        let queue: [Song]
        let isPlaying: Bool
        let isRadio: Bool
        let isShuffled: Bool
        let repeatSetting: CompanionPlayback.RepeatSetting
        let error: String?
        let sleepDeadline: Date?
        let sleepAtEndOfSong: Bool
    }

    private func repeatSetting(_ mode: RepeatMode) -> CompanionPlayback.RepeatSetting {
        switch mode {
        case .off: .off
        case .one: .one
        case .all: .all
        }
    }

    private func publishPlayback() {
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let snapshot = playbackSnapshot()
        guard let data = CompanionPlayback.encode(snapshot) else { return }
        if session.isReachable {
            session.sendMessage([CompanionPlayback.contextKey: data], replyHandler: nil)
        }
        var context = session.applicationContext
        context[CompanionPlayback.contextKey] = data
        context[CompanionPlayback.takeoverRequestKey] = pendingTakeover.flatMap { CompanionPlayback.encode($0) }
        try? session.updateApplicationContext(context)
    }

    @discardableResult
    func routeToWatch(_ action: CompanionPlayback.Action, song: Song? = nil,
                      queue: [Song]? = nil, position: Double? = nil,
                      streamURL: URL? = nil, artworkURL: URL? = nil, shuffleEnabled: Bool? = nil,
                      sleepMinutes: Int? = nil, sleepAtEndOfSong: Bool? = nil) -> Bool {
        guard watchOwnsAudio else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            requestPhoneTakeover()
            AudioPlayerManager.shared.companionFailure("Waiting for Apple Watch to stop. Bring it nearby, then try playback again on iPhone.")
            return true
        }
        commandSequence += 1
        let sentLease = lease
        let command = CompanionPlayback.Command(sessionID: lease.sessionID,
            clientID: commandClientID, sequence: commandSequence,
            baseRevision: watchSnapshot?.revision, action: action, song: song, queue: queue, position: position,
            streamURL: streamURL, artworkURL: artworkURL, ownershipEpoch: lease.epoch,
            accountGeneration: currentGeneration, phoneInstanceID: phoneInstanceID, shuffleEnabled: shuffleEnabled,
            sleepMinutes: sleepMinutes, sleepAtEndOfSong: sleepAtEndOfSong)
        guard let data = CompanionPlayback.encode(command) else { return true }
        session.sendMessage([CompanionPlayback.messageDataKey: data], replyHandler: { @Sendable [weak self] reply in
            let snapshot = CompanionPlayback.decode(CompanionPlayback.Snapshot.self,
                from: reply[CompanionPlayback.replyDataKey] as? Data)
            let error = reply[CompanionPlayback.errorKey] as? String
            Task { @MainActor [weak self] in
                if let snapshot { self?.acceptWatchSnapshot(snapshot) }
                if let error { AudioPlayerManager.shared.companionFailure(error) }
            }
        }, errorHandler: { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.lease == sentLease else { return }
                self.requestPhoneTakeover()
                AudioPlayerManager.shared.companionFailure("Waiting for Apple Watch to stop. Bring it nearby, then try playback again on iPhone.")
            }
        })
        return true
    }

    private func acceptWatchSnapshot(_ snapshot: CompanionPlayback.Snapshot) {
        guard snapshot.belongsToAccount(generation: currentGeneration, phoneInstanceID: phoneInstanceID),
              lease.owner == .watch, lease.accepts(snapshot), snapshot.supersedes(watchSnapshot) else { return }
        watchSnapshot = snapshot
        defaults.set(CompanionPlayback.encode(snapshot), forKey: "nk.phone.watchPlayback")
        AudioPlayerManager.shared.applyWatchSnapshot(snapshot)
    }

    private func handle(_ command: CompanionPlayback.Command) -> [String: Any] {
        let player = AudioPlayerManager.shared
        guard command.accountGeneration == currentGeneration, command.phoneInstanceID == phoneInstanceID else {
            return reply(error: "Account changed. Wait for account sync and try again.")
        }
        guard command.ownershipEpoch == nil || command.ownershipEpoch == lease.epoch else {
            return reply(error: "Audio output changed. Try again.")
        }
        // Transfer commands are idempotent; an acknowledgement lost in transit
        // must never make either side resume its former output.
        if command.action == .transferToWatch, lease.owner == .watch { return reply() }
        if command.action == .transferToPhone, lease.owner == .phone { return reply() }
        if lease.owner == .watch, command.action != .transferToPhone { return reply() }
        switch commandGate.decide(
            command, sessionID: playbackSessionID, revision: playbackRevision,
            lastPhoneChangeAt: lastPhoneStructuralChangeAt
        ) {
        case .duplicate: return reply()
        case .stale:
            return reply(error: "Playback changed on iPhone. Try again.")
        case .accept: break
        }
        isApplyingWatchCommand = true
        defer { isApplyingWatchCommand = false }
        switch command.action {
        case .transferToWatch:
            var state = playbackSnapshot()
            player.suspendForWatchTransfer()
            lease.transfer(to: .watch)
            CompanionPlayback.saveLease(lease)
            state.owner = .watch
            state.ownershipEpoch = lease.epoch
            state.revision += 1
            state.isPlaying = false
            state.updatedAt = Date()
            watchSnapshot = state
            defaults.set(CompanionPlayback.encode(state), forKey: "nk.phone.watchPlayback")
            player.applyWatchSnapshot(state)
        case .transferToPhone:
            // The watch stops before sending this command. Returning ownership
            // leaves both paused until an explicit Play on the chosen output.
            let state = playbackSnapshot()
            lease.transfer(to: .phone)
            CompanionPlayback.saveLease(lease)
            finishPhoneTransfer(state)
        case .replaceQueue:
            player.replaceCompanionQueue(command.queue ?? [])
        case .playNext:
            if let song = command.song { player.playNext(song: song) }
        case .playLast:
            if let song = command.song { player.playLast(song: song) }
        case .play:
            guard let song = command.song, song.audioURL != nil else {
                return reply(error: "This song has no playable audio. Choose another song.")
            }
            if command.shuffleEnabled == true {
                player.playCompanion(song: song, context: command.queue ?? [song], shuffled: true)
            } else {
                player.playInOrder(song: song, context: command.queue ?? [song])
            }
        case .sleepTimer:
            if command.sleepAtEndOfSong == true { player.startSleepTimerAtEndOfSong() }
            else { player.setSleepTimer(minutes: command.sleepMinutes) }
        case .pause: player.pauseIfPlaying()
        case .resume:
            if !player.isPlaying { _ = player.togglePlayPause(source: "watch") }
        case .next: player.skipToNext()
        case .previous: player.playPrevious()
        case .seek:
            guard let position = command.position, position.isFinite else { return reply() }
            let duration = player.playbackDuration
            if duration > 0 { player.seek(to: min(max(position / duration, 0), 1)) }
        case .radio:
            guard let song = command.song, let url = command.streamURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return reply(error: "The radio stream is unavailable. Try again later.")
            }
            player.playRadio(streamURL: url, song: song, artworkURL: command.artworkURL)
        case .stopRadio: player.stopRadioPlayback()
        case .shuffle: player.toggleShuffle()
        case .repeatMode: player.toggleRepeat()
        }
        publishPlayback()
        return reply()
    }

    private func reply(error: String? = nil) -> [String: Any] {
        var result: [String: Any] = [:]
        if let data = CompanionPlayback.encode(playbackSnapshot()) {
            result[CompanionPlayback.replyDataKey] = data
        }
        if let error { result[CompanionPlayback.errorKey] = error }
        return result
    }

    // MARK: - Publishing

    /// Persist only a request to stop. Offline watch grants remain valid until
    /// that exact grant is acknowledged, even across either app's relaunch.
    private func requestPhoneTakeover() {
        guard lease.owner == .watch else { return }
        pendingTakeover = lease
        defaults.set(CompanionPlayback.encode(lease), forKey: Self.takeoverKey)
        publishPlayback()
    }

    private func acceptTakeoverAck(_ stopped: CompanionPlayback.Lease) {
        let state = playbackSnapshot()
        guard lease.reclaimAfterStop(stopped, requested: pendingTakeover) else { return }
        CompanionPlayback.saveLease(lease)
        finishPhoneTransfer(state)
        publishPlayback()
    }

    private func finishPhoneTransfer(_ state: CompanionPlayback.Snapshot) {
        AudioPlayerManager.shared.finishWatchTransfer(state)
        watchSnapshot = nil
        pendingTakeover = nil
        defaults.removeObject(forKey: "nk.phone.watchPlayback")
        defaults.removeObject(forKey: Self.takeoverKey)
        lastPlaybackFingerprint = nil
    }

    /// - Parameter bumpingGeneration: `true` for a genuine session change, so
    ///   the watch knows to re-pull the token. `false` when merely resending
    ///   the state we already published (activation, watch app installed).
    private func publish(bumpingGeneration: Bool) {
        // Recorded before the guards below, because the guards are about
        // whether anyone is listening, not about whether the change happened.
        // Signing out and back in as the same user with the watch unpaired
        // used to leave the generation untouched, and the resend that follows
        // reconnection carries `bumpingGeneration: false` — so the watch saw
        // the number it had already applied and kept the old session's token.
        if bumpingGeneration {
            defaults.set(currentGeneration + 1, forKey: Self.generationKey)
            watchSnapshot = nil
            defaults.removeObject(forKey: "nk.phone.watchPlayback")
            if watchOwnsAudio { AudioPlayerManager.shared.applyWatchSnapshot(playbackSnapshot()) }
        }

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Nothing to talk to yet; `sessionWatchStateDidChange` republishes once
        // a watch is paired and the app installed.
        guard session.isPaired, session.isWatchAppInstalled else { return }

        guard var descriptor = AuthManager.persistedDescriptor() else {
            // A temporarily unreadable Keychain must not block playback
            // reconnection or erase the last known account context.
            publishPlayback()
            return
        }
        descriptor.generation = currentGeneration
        descriptor.phoneInstanceID = phoneInstanceID

        do {
            var context = session.applicationContext
            context.removeValue(forKey: WatchSessionLink.ContextKey.userID)
            context.removeValue(forKey: WatchSessionLink.ContextKey.username)
            context.removeValue(forKey: WatchSessionLink.ContextKey.avatar)
            context.merge(WatchSessionLink.encode(descriptor)) { _, new in new }
            if let data = CompanionPlayback.encode(playbackSnapshot()) {
                context[CompanionPlayback.contextKey] = data
            }
            try session.updateApplicationContext(context)
            publishPlayback()
        } catch {
            DebugLogger.log(
                "Watch session context failed: \(error.localizedDescription)",
                category: .network
            )
        }
    }

    private var currentGeneration: Int {
        defaults.integer(forKey: Self.generationKey)
    }
}

extension WatchSessionPublisher: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {
        // The watch may have missed changes while unpaired or the app was gone;
        // resend the current state without claiming it is new.
        Task { @MainActor [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    nonisolated func sessionWatchStateDidChange(_: WCSession) {
        Task { @MainActor [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in
            await FavoritesManager.shared.refreshFromCompanion()
            self?.publish(bumpingGeneration: false)
        }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_: WCSession) {
        // Switching to a different paired watch: reactivate so the new one
        // receives the session too.
        WCSession.default.activate()
    }

    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let kind = message[WatchSessionLink.MessageKey.kind] as? String
        if kind == WatchSessionLink.MessageKind.fetchToken {
            let reply = WatchReplyBox(replyHandler)
            let generation = message["generation"] as? Int
            let messageInstanceID = message[WatchSessionLink.ContextKey.phoneInstanceID] as? String
            let userID = (message["userID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            Task { @MainActor [weak self] in
                guard let self, var descriptor = AuthManager.persistedDescriptor() else {
                    reply.send([WatchSessionLink.MessageKey.credentialUnavailable: true]); return
                }
                descriptor.generation = self.currentGeneration
                descriptor.phoneInstanceID = self.phoneInstanceID
                var response = WatchSessionLink.encode(descriptor)
                if !descriptor.isSignedIn {
                    response[WatchSessionLink.MessageKey.isSignedIn] = false
                } else if WatchSessionLink.tokenRequestMatches(generation: generation, userID: userID,
                    descriptor: descriptor, currentGeneration: self.currentGeneration,
                    phoneInstanceID: messageInstanceID) {
                    response.merge(WatchSessionLink.tokenReply(for: CredentialStore.readToken())) { _, new in new }
                } else {
                    response[WatchSessionLink.MessageKey.credentialUnavailable] = true
                }
                reply.send(response)
            }
        } else if kind == WatchSessionLink.MessageKind.fetchPlaylists {
            let reply = WatchReplyBox(replyHandler)
            let generation = message["generation"] as? Int
            let messageInstanceID = message[WatchSessionLink.ContextKey.phoneInstanceID] as? String
            let userID = message["userID"] as? String
            Task { @MainActor [weak self] in
                guard let self, generation == self.currentGeneration, messageInstanceID == self.phoneInstanceID,
                      let account = AuthManager.persistedDescriptor(), account.isSignedIn,
                      account.userID == userID else { reply.send([:]); return }
                do {
                    let request = try KaraokeAPIClient.request(path: "/api/user/playlists")
                    let data = try await KaraokeAPIClient.data(for: request)
                    let playlists = try JSONDecoder().decode([UserPlaylist].self, from: data)
                    guard generation == self.currentGeneration, messageInstanceID == self.phoneInstanceID,
                          AuthManager.persistedDescriptor()?.userID == userID,
                          let encoded = CompanionPlayback.encode(playlists), encoded.count < 60_000 else {
                        reply.send([:]); return
                    }
                    reply.send(["playlists": encoded])
                } catch { reply.send([:]) }
            }
        } else if kind == WatchSessionLink.MessageKind.fetchAccount {
            let reply = WatchReplyBox(replyHandler)
            Task { @MainActor [weak self] in
                guard let self else { reply.send([:]); return }
                guard var descriptor = AuthManager.persistedDescriptor() else {
                    reply.send([WatchSessionLink.MessageKey.credentialUnavailable: true])
                    return
                }
                descriptor.generation = UserDefaults.standard.integer(forKey: Self.generationKey)
                descriptor.phoneInstanceID = self.phoneInstanceID
                reply.send(WatchSessionLink.encode(descriptor))
            }
        } else if kind == CompanionPlayback.messageKind,
                  let command = CompanionPlayback.decode(
                    CompanionPlayback.Command.self,
                    from: message[CompanionPlayback.messageDataKey] as? Data
                  ) {
            let reply = WatchReplyBox(replyHandler)
            Task { @MainActor [weak self] in
                reply.send(self?.handle(command) ?? [:])
            }
        } else {
            replyHandler([:])
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if let stopped = CompanionPlayback.decode(CompanionPlayback.Lease.self,
            from: message[CompanionPlayback.takeoverAckKey] as? Data) {
            Task { @MainActor [weak self] in self?.acceptTakeoverAck(stopped) }
            return
        }
        if message[WatchSessionLink.MessageKey.kind] as? String == WatchSessionLink.MessageKind.favoritesChanged {
            let userID = message[WatchSessionLink.ContextKey.userID] as? String
            Task { @MainActor in
                guard let account = AuthManager.persistedDescriptor(), account.isSignedIn,
                      userID != nil, account.userID == userID else { return }
                await FavoritesManager.shared.refreshFromCompanion()
            }
            return
        }
        let snapshot = CompanionPlayback.decode(CompanionPlayback.Snapshot.self,
            from: message[CompanionPlayback.contextKey] as? Data)
        Task { @MainActor [weak self] in
            if let snapshot { self?.acceptWatchSnapshot(snapshot) }
        }
    }
    nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let snapshot = CompanionPlayback.decode(CompanionPlayback.Snapshot.self,
            from: context[CompanionPlayback.contextKey] as? Data)
        Task { @MainActor [weak self] in
            if let snapshot { self?.acceptWatchSnapshot(snapshot) }
        }
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let stopped = CompanionPlayback.decode(CompanionPlayback.Lease.self,
            from: userInfo[CompanionPlayback.takeoverAckKey] as? Data) else { return }
        Task { @MainActor [weak self] in self?.acceptTakeoverAck(stopped) }
    }

}
