import Foundation
import WatchConnectivity
import UIKit

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

    private let defaults = UserDefaults.standard
    private var restorationObservers: [NSObjectProtocol] = []
    private var sessionChangedObserver: NSObjectProtocol?

    override private init() { super.init() }
    func activate() {
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
                Task { @MainActor [weak self] in self?.publish(bumpingGeneration: false) }
            }
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    private func publish(bumpingGeneration: Bool) {
        if bumpingGeneration {
            defaults.set(currentGeneration + 1, forKey: Self.generationKey)
        }

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        guard var descriptor = AuthManager.persistedDescriptor() else { return }
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
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    nonisolated func sessionWatchStateDidChange(_: WCSession) {
        Task { @MainActor [weak self] in
            self?.publish(bumpingGeneration: false)
        }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(
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

        replyHandler(WatchSessionLink.tokenReply(for: CredentialStore.readToken()))
    }
}
