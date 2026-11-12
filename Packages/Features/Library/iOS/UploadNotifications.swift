import UIKit
import UserNotifications

/// A local notification for an upload or link import that ends while the
/// app isn't active, as downloads have. It follows the download notification
/// setting and the permission that setting asked for: there is no second
/// prompt. Tests replace it, so they never post a real notification.
struct UploadNotifier {
    /// What one notification says.
    struct Content: Equatable {
        let identifier: String
        let title: String
        let body: String
    }

    var isEnabled: @MainActor () -> Bool
    var isAppActive: @MainActor () -> Bool
    var deliver: @MainActor (_ content: Content) async -> Void

    static var live: UploadNotifier {
        UploadNotifier(
            isEnabled: { DownloadNotifications.shared.isEnabled },
            isAppActive: { UIApplication.shared.applicationState == .active },
            deliver: { content in
                let notification = UNMutableNotificationContent()
                notification.title = content.title
                notification.body = content.body
                notification.sound = .default
                let request = UNNotificationRequest(identifier: content.identifier, content: notification, trigger: nil)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    DebugLogger.log("Upload notification failed: \(type(of: error))", category: .network)
                }
            }
        )
    }

    /// Never posts; for UI tests.
    static var disabled: UploadNotifier {
        UploadNotifier(isEnabled: { false }, isAppActive: { true }, deliver: { _ in })
    }

    /// The notification for `completion`, in the app's chosen language. Its
    /// identifier is the upload's, so one upload never stacks two.
    static func content(for completion: SongUploadCompletion, defaults: UserDefaults = .standard) -> Content {
        // As for downloads: outside SwiftUI the bundle picks the translation.
        let localization = UploadLocalization.current(defaults)
        let (bundle, locale) = (localization.bundle, localization.locale)
        let song = completion.title
        let body = switch (completion.succeeded, song.isEmpty) {
        case (true, false): String(localized: "Added “\(song)” to your uploads.", bundle: bundle, locale: locale)
        case (true, true): String(localized: "Your upload finished.", bundle: bundle, locale: locale)
        case (false, false): String(localized: "“\(song)” couldn't be uploaded.", bundle: bundle, locale: locale)
        case (false, true): String(localized: "An upload failed.", bundle: bundle, locale: locale)
        }
        return Content(
            identifier: "nk.uploadCompletion.\(completion.itemID.uuidString)",
            title: String(localized: "Uploads", bundle: bundle, locale: locale),
            body: body
        )
    }
}

extension SongUploadController {
    /// Notifies once per upload that ends while the app isn't active,
    /// including one settled during a background wake. Not for an upload of
    /// an account that has since signed out.
    func notifyIfInBackground(_ completion: Completion) {
        let notifier = service.notifier
        guard notifier.isEnabled(), !notifier.isAppActive(),
              records[completion.itemID]?.endsUnseen != true,
              notifiedUploads.insert(completion.itemID).inserted
        else { return }
        let content = UploadNotifier.content(for: completion)
        let id = completion.itemID
        notificationTasks[id] = Task { [weak self] in
            await notifier.deliver(content)
            self?.notificationTasks[id] = nil
        }
    }

    /// Waits for notifications still being posted, so a background wake
    /// doesn't end, and the app get suspended, before they are.
    func finishNotifications() async {
        for task in Array(notificationTasks.values) {
            await task.value
        }
    }
}
