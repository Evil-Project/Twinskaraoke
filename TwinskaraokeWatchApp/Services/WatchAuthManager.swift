import Combine
import Foundation
import WatchConnectivity

/// Watch half of the session bridge (see `WatchSessionLink`).
///
/// The watch never authenticates by itself. It mirrors whatever session the
/// phone reports: identity arrives in the application context, and the bearer
/// token is pulled separately and kept only in this device's Keychain, where
/// `KaraokeAPIClient` picks it up for every request.
@MainActor
final class WatchAuthManager: NSObject, ObservableObject {
    static let shared = WatchAuthManager()

    /// How the watch describes its own link to the phone, so the account
    /// screen can distinguish "you aren't signed in" from "I can't reach your
    /// phone to finish signing you in".
    enum LinkState: Equatable {
        case signedOut
        case signedIn
        case awaitingPhone
    }

    @Published private(set) var linkState: LinkState = .signedOut
    @Published private(set) var username: String?
    @Published private(set) var userID: String?
    @Published private(set) var avatarURL: URL?
    @Published private(set) var isSyncing = false

    private enum Key {
        static let username = "nk.watch.username"
        static let userID = "nk.watch.userId"
        static let avatar = "nk.watch.avatar"
        static let generation = "nk.watch.appliedGeneration"
    }

    private let defaults = UserDefaults.standard
    /// Set while a descriptor says we are signed in but no token has landed
    /// yet, so reachability changes know there is work to retry.
    private var needsToken = false

    override private init() {
        super.init()
        restoreCachedIdentity()
    }

    /// Safe to call more than once; only the first call takes effect.
    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Manual retry for the account screen, for when the phone was out of
    /// range while a session change came through.
    func syncNow() {
        guard CredentialStore.token == nil else { return }
        needsToken = true
        requestToken()
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
        guard descriptor.isSignedIn else {
            clearSession()
            return
        }

        let appliedGeneration = defaults.integer(forKey: Key.generation)
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

        if identityChanged, userID != nil {
            // Different account than the one cached: drop the old token rather
            // than leaving it usable until the new one arrives.
            CredentialStore.deleteToken()
        }

        username = descriptor.username
        userID = descriptor.userID
        avatarURL = descriptor.avatar.flatMap(URL.init(string:))
        defaults.set(descriptor.username, forKey: Key.username)
        defaults.set(descriptor.userID, forKey: Key.userID)
        defaults.set(descriptor.avatar, forKey: Key.avatar)
        defaults.set(descriptor.generation, forKey: Key.generation)

        if needsFreshToken {
            needsToken = true
            linkState = CredentialStore.token == nil ? .awaitingPhone : .signedIn
            requestToken()
        } else {
            linkState = .signedIn
        }
    }

    private func clearSession() {
        CredentialStore.deleteToken()
        // Anything fetched while signed in was scoped to that account.
        FavoritesManager.shared.clear()
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
        session.sendMessage(
            [WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.fetchToken],
            replyHandler: { [weak self] reply in
                let signedIn = reply[WatchSessionLink.MessageKey.isSignedIn] as? Bool ?? false
                let token = reply[WatchSessionLink.MessageKey.token] as? String
                Task { @MainActor [weak self] in
                    self?.receive(token: token, signedIn: signedIn)
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Leave `needsToken` set so the next reachability change or
                    // manual sync tries again.
                    self?.isSyncing = false
                }
            }
        )
    }

    private func receive(token: String?, signedIn: Bool) {
        isSyncing = false
        guard signedIn, let token, !token.isEmpty else {
            // The phone signed out between publishing the context and our pull.
            clearSession()
            return
        }
        do {
            try CredentialStore.saveToken(token)
            // Whatever was fetched as a guest is now the wrong scope.
            Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
            // Star state is account-scoped and now fetchable for the first time.
            FavoritesManager.shared.reload()
            needsToken = false
            linkState = .signedIn
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
            self?.requestToken()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in
            self?.requestToken()
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
        // Decoded here, off the main actor, because `[String: Any]` cannot
        // cross actors but `Descriptor` can.
        guard let descriptor = WatchSessionLink.decode(context) else { return }
        Task { @MainActor [weak self] in
            self?.apply(descriptor)
        }
    }
}
