import Foundation
import WatchConnectivity
import Observation
@MainActor
@Observable
final class WatchAuthManager: NSObject {
    static let shared = WatchAuthManager()
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

    private enum Key {
        static let username = "nk.watch.username"
        static let userID = "nk.watch.userId"
        static let avatar = "nk.watch.avatar"
        static let generation = "nk.watch.appliedGeneration"
    }

    private let defaults = UserDefaults.standard
    private var needsToken = false

    override private init() {
        super.init()
        restoreCachedIdentity()
    }
    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func syncNow() {
        guard CredentialStore.token == nil else { return }
        needsToken = true
        requestToken()
    }

    private func restoreCachedIdentity() {
        username = defaults.string(forKey: Key.username)
        userID = defaults.string(forKey: Key.userID)
        avatarURL = defaults.string(forKey: Key.avatar).flatMap(URL.init(string:))
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
        let needsFreshToken = descriptor.generation != appliedGeneration
            || identityChanged
            || CredentialStore.token == nil

        if identityChanged, userID != nil {
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

    private func requestToken() {
        guard needsToken, !isSyncing else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }

        isSyncing = true
        session.sendMessage(
            [WatchSessionLink.MessageKey.kind: WatchSessionLink.MessageKind.fetchToken],
            replyHandler: { [weak self] reply in
                let result = WatchSessionLink.decodeTokenReply(reply)
                Task { @MainActor [weak self] in
                    switch result {
                    case .available(let token): self?.receive(token: token, signedIn: true)
                    case .signedOut: self?.receive(token: nil, signedIn: false)
                    case .unavailable: self?.isSyncing = false
                    }
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSyncing = false
                }
            }
        )
    }

    private func receive(token: String?, signedIn: Bool) {
        isSyncing = false
        guard signedIn, let token, !token.isEmpty else {
            clearSession()
            return
        }
        do {
            try CredentialStore.saveToken(token)
            Task { await KaraokeAPIClient.invalidateAccountScopedCaches() }
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
        guard let descriptor = WatchSessionLink.decode(context) else { return }
        Task { @MainActor [weak self] in
            self?.apply(descriptor)
        }
    }
}
