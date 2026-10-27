import Foundation
import Testing
import UserNotifications
@testable import Twinskaraoke

@MainActor
@Suite("Settings behavior", .serialized)
struct SettingsBehaviorTests {
    @Test("Autoplay preserves recommendation order and excludes invalid or duplicate candidates")
    func autoplayCandidates() {
        let songs = [song("current"), song("first"), song("first"), song("missing", source: nil), song("second")]
        #expect(AutoplaySelection.playableSongs(songs, excluding: "current").map(\.id) == ["first", "second"])
        #expect(AutoplaySelection.playableSongs([song("current")], excluding: "current").isEmpty)
    }

    @Test("First Shimeji edit preserves the other default-enabled characters")
    func shimejiDefaultSelection() {
        var settings = ShimejiSpawnSettings(enabledCharacterIDs: [], maxCount: 3)
        #expect(settings.enabledIDs(for: manifest) == ["a", "b"])
        settings.setCharacter("a", enabled: false, manifest: manifest)
        #expect(settings.enabledIDs(for: manifest) == ["b"])
        settings.setCharacter("b", enabled: false, manifest: manifest)
        #expect(settings.enabledIDs(for: manifest).isEmpty)
        settings.setCharacter("a", enabled: true, manifest: manifest)
        #expect(settings.enabledIDs(for: manifest) == ["a"])
    }

    @Test("Explicit empty and legacy nonempty Shimeji selections survive edits and encoding")
    func shimejiPersistence() throws {
        var settings = ShimejiSpawnSettings(enabledCharacterIDs: ["a"], maxCount: 3)
        #expect(settings.enabledIDs(for: manifest) == ["a"])
        settings.setCharacter("a", enabled: false, manifest: manifest)
        let restored = try JSONDecoder().decode(ShimejiSpawnSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.enabledIDs(for: manifest).isEmpty)
    }

    @Test("Out-of-range Shimeji counts cannot create an invalid spawn range", arguments: [-5, 0, 8, 100])
    func shimejiCount(_ count: Int) {
        let settings = ShimejiSpawnSettings(enabledCharacterIDs: [], maxCount: count)
        #expect(ShimejiSpawnSettings.countRange.contains(settings.clampedCount))
    }

    @Test("Old inert notification preference does not silently opt the user in")
    func notificationMigration() {
        withDefaults { defaults in
            defaults.set(true, forKey: "nk.notifications.downloads")
            let notifications = DownloadNotifications(defaults: defaults, center: FakeNotificationCenter())
            #expect(!notifications.isEnabled)
        }
    }

    @Test("Notification permission denial leaves the preference off")
    func notificationDenial() async {
        let suite = "settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = FakeNotificationCenter()
        center.allowed = false
        center.status = .denied
        let notifications = DownloadNotifications(defaults: defaults, center: center)
        await notifications.setEnabled(true)
        #expect(!notifications.isEnabled)
        #expect(notifications.permissionDenied)
        #expect(!notifications.isUpdating)
        #expect(!defaults.bool(forKey: DownloadNotifications.storageKey))
    }

    @Test("Notification opt-in persists, delivers completion, and disabling clears pending notifications")
    func notificationLifecycle() async {
        let suite = "settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = FakeNotificationCenter()
        let notifications = DownloadNotifications(defaults: defaults, center: center)
        defaults.set("de", forKey: AppLanguage.storageKey)
        await notifications.sendCompletion(completed: 2, failed: 0)
        #expect(center.requests.isEmpty)
        await notifications.setEnabled(true)
        #expect(DownloadNotifications(defaults: defaults, center: center).isEnabled)
        await notifications.sendCompletion(completed: 0, failed: 0)
        #expect(center.requests.isEmpty)
        await notifications.sendCompletion(completed: 2, failed: 0)
        #expect(center.requests.count == 1)
        #expect(center.requests.first?.content.body == "Deine Songs sind zum Offline-Hören bereit.")
        await notifications.setEnabled(false)
        #expect(center.clearCount == 1)
        #expect(!DownloadNotifications(defaults: defaults, center: center).isEnabled)
        await notifications.sendCompletion(completed: 2, failed: 0)
        #expect(center.requests.count == 1)
    }

    @Test("Turning notifications off during delivery clears the in-flight notification too")
    func notificationDeliveryRace() async {
        let suite = "settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = FakeNotificationCenter()
        let notifications = DownloadNotifications(defaults: defaults, center: center)
        await notifications.setEnabled(true)
        center.onAdd = { await notifications.setEnabled(false) }
        await notifications.sendCompletion(completed: 1, failed: 0)
        #expect(!notifications.isEnabled)
        #expect(center.clearCount == 2)
        center.onAdd = nil
    }

    @Test("Permission errors are reported without leaving controls busy")
    func notificationError() async {
        let suite = "settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = FakeNotificationCenter()
        center.shouldThrow = true
        let notifications = DownloadNotifications(defaults: defaults, center: center)
        await notifications.setEnabled(true)
        #expect(notifications.hasError)
        #expect(!notifications.isUpdating)
        #expect(!notifications.isEnabled)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    private func song(_ id: String, source: String? = "https://example.com/song.mp3") -> Song {
        Song(id: id, title: id, duration: 60, absolutePath: source, cloudflareID: nil,
             coverArt: nil, originalArtists: nil, coverArtists: nil, userUploaded: false)
    }

    private var manifest: ShimejiManifest {
        ShimejiManifest(formatVersion: 1, packName: "Test", characters: ["a", "b"].map {
            ShimejiCharacterDefinition(id: $0, displayName: $0, folder: $0, frameSize: 128,
                                       anchor: ShimejiAnchor(x: 64, y: 128), actions: [:])
        })
    }
}

@MainActor
private final class FakeNotificationCenter: DownloadNotificationCenter {
    var status: UNAuthorizationStatus = .authorized
    var allowed = true
    var shouldThrow = false
    var requests: [UNNotificationRequest] = []
    var clearCount = 0
    var onAdd: (() async -> Void)?

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        if shouldThrow { throw URLError(.unknown) }
        return allowed
    }
    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
        await onAdd?()
    }
    func clearCompletionNotifications() { clearCount += 1 }
}
