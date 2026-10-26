import Observation
import UIKit
import UserNotifications

@MainActor
protocol DownloadNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func clearCompletionNotifications()
}

@MainActor
private struct SystemDownloadNotificationCenter: DownloadNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
    func clearCompletionNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [DownloadNotifications.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [DownloadNotifications.requestID])
    }
}

@MainActor
@Observable
final class DownloadNotifications {
    static let shared = DownloadNotifications()
    // The old notifications.downloads key was an inert, default-on switch.
    // Require an explicit opt-in to the newly implemented notification feature.
    static let storageKey = "nk.notifications.downloadCompletion"
    fileprivate static let requestID = "nk.downloadCompletion"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: any DownloadNotificationCenter
    private(set) var isEnabled: Bool
    private(set) var isUpdating = false
    private(set) var permissionDenied = false
    var hasError = false

    init(defaults: UserDefaults = .standard, center: (any DownloadNotificationCenter)? = nil) {
        self.defaults = defaults
        self.center = center ?? SystemDownloadNotificationCenter()
        isEnabled = defaults.bool(forKey: Self.storageKey)
    }

    func refreshAuthorization() async {
        permissionDenied = await center.authorizationStatus() == .denied
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        if enabled {
            do {
                let allowed = try await center.requestAuthorization()
                await refreshAuthorization()
                guard allowed else { return }
            } catch {
                hasError = true
                return
            }
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.storageKey)
        if !enabled {
            center.clearCompletionNotifications()
        }
    }

    func downloadsFinished(completed: Int, failed: Int) {
        guard isEnabled, completed + failed > 0, !AppRuntime.isUITestMode,
              UIApplication.shared.applicationState != .active else { return }
        Task { await sendCompletion(completed: completed, failed: failed) }
    }

    func sendCompletion(completed: Int, failed: Int) async {
        guard isEnabled, completed + failed > 0 else { return }
        let content = UNMutableNotificationContent()
        let language = AppLanguage(rawValue: defaults.string(forKey: AppLanguage.storageKey) ?? "system") ?? .system
        let locale = Locale(identifier: language.localeIdentifier)
        // String's locale formats interpolated values; the bundle determines
        // which translation is loaded outside SwiftUI's locale environment.
        let bundle = language.localizationBundle
        content.title = String(localized: "Downloads", bundle: bundle, locale: locale)
        content.body = failed == 0
            ? String(localized: "Your songs are ready for offline listening.", bundle: bundle, locale: locale)
            : String(localized: "Some songs could not be downloaded. Open the app to retry.", bundle: bundle, locale: locale)
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        do {
            try await center.add(request)
            // An off toggle may have interleaved while add was awaiting.
            if !isEnabled {
                center.clearCompletionNotifications()
            }
        } catch {
            DebugLogger.log("Download notification failed: \(error)", category: .network)
        }
    }
}
