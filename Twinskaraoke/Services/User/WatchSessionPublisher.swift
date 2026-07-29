import Foundation
import WatchConnectivity

/// Phone half of the watch session bridge (see `WatchSessionLink`).
///
/// Publishes the non-secret session descriptor to the watch as an application
/// context, and answers the watch's transient request for the bearer token.
/// Activated once at launch and lives for the process: `AuthManager` instances
/// come and go with `AccountView`, so session changes arrive by notification.
final class WatchSessionPublisher: NSObject {
    static let shared = WatchSessionPublisher()

    private static let generationKey = "nk.watchSessionGeneration"

    private let defaults = UserDefaults.standard
    private var sessionChangedObserver: NSObjectProtocol?

    override private init() { super.init() }

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
            self?.publish(bumpingGeneration: true)
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Publishing

    /// - Parameter bumpingGeneration: `true` for a genuine session change, so
    ///   the watch knows to re-pull the token. `false` when merely resending
    ///   the state we already published (activation, watch app installed).
    private func publish(bumpingGeneration: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Nothing to talk to yet; `sessionWatchStateDidChange` republishes once
        // a watch is paired and the app installed.
        guard session.isPaired, session.isWatchAppInstalled else { return }

        if bumpingGeneration {
            defaults.set(currentGeneration + 1, forKey: Self.generationKey)
        }

        var descriptor = AuthManager.persistedDescriptor()
        descriptor.generation = currentGeneration

        do {
            try session.updateApplicationContext(WatchSessionLink.encode(descriptor))
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
    func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {
        // The watch may have missed changes while unpaired or the app was gone;
        // resend the current state without claiming it is new.
        DispatchQueue.main.async { [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    func sessionWatchStateDidChange(_: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {
        // Switching to a different paired watch: reactivate so the new one
        // receives the session too.
        WCSession.default.activate()
    }

    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[WatchSessionLink.MessageKey.kind] as? String
            == WatchSessionLink.MessageKind.fetchToken
        else {
            replyHandler([:])
            return
        }

        // Read the Keychain rather than any cached flag, so a session the user
        // has already signed out of can never be handed to the watch.
        guard let token = CredentialStore.token, !token.isEmpty else {
            replyHandler([WatchSessionLink.MessageKey.isSignedIn: false])
            return
        }
        replyHandler([
            WatchSessionLink.MessageKey.isSignedIn: true,
            WatchSessionLink.MessageKey.token: token,
        ])
    }
}
