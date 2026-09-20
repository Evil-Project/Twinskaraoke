import Foundation
import Observation
import UIKit

/// How far into a video the viewer got, kept so it can be resumed later.
///
/// Carries the `GalleryVideo` rather than just its ID so the Continue Watching
/// shelf can render without the catalogue: `/api/videos` pages 25 at a time
/// through ~1400 items, so a video watched last month is almost never among the
/// pages currently loaded.
nonisolated struct VideoResumePoint: Codable, Equatable, Sendable, Identifiable {
    let video: GalleryVideo
    let position: TimeInterval
    let duration: TimeInterval
    let updatedAt: Date

    var id: String { video.id }
    var fraction: Double? {
        guard duration > 0 else { return nil }
        return min(1, max(0, position / duration))
    }
    var remaining: TimeInterval? {
        guard duration > 0 else { return nil }
        return max(0, duration - position)
    }
}
nonisolated enum VideoWatchOutcome: Equatable, Sendable {
    case resume
    case watched
    case discard
}
@MainActor
@Observable
final class VideoResumeStore {
    static let shared = VideoResumeStore()
    nonisolated static let minimumPosition: TimeInterval = 10
    nonisolated static let completionTail: TimeInterval = 10
    nonisolated static let entryLimit = 60
    nonisolated static let watchedLimit = 500
    private(set) var points: [String: VideoResumePoint] = [:]
    private(set) var watched: [String: Date] = [:]
    var continueWatching: [VideoResumePoint] {
        points.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var account: String?
    private var sessionObservers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard
    private let isEnabled = !AppRuntime.isUITestMode

    private init() {
        account = Self.currentAccount()
        guard isEnabled else { return }
        load()
        sessionObservers = [WatchSessionLink.sessionChanged,
                            UIApplication.didBecomeActiveNotification,
                            UIApplication.protectedDataDidBecomeAvailableNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.rebindAccount() }
            }
        }
    }

    isolated deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
    }
    func point(for videoID: String) -> VideoResumePoint? {
        points[videoID]
    }

    func isWatched(_ videoID: String) -> Bool {
        watched[videoID] != nil
    }
    func record(_ video: GalleryVideo, position: TimeInterval, duration: TimeInterval) {
        guard !video.id.isEmpty, position.isFinite, position >= 0 else { return }
        let duration = duration.isFinite && duration > 0 ? duration : 0

        switch Self.outcome(position: position, duration: duration) {
        case .discard:
            clear(videoID: video.id)
        case .watched:
            markWatched(video.id)
        case .resume:
            var updated = points
            updated[video.id] = VideoResumePoint(
                video: video,
                position: position,
                duration: duration,
                updatedAt: Date()
            )
            points = Self.trimmed(updated)
            watched[video.id] = nil
            save()
        }
    }
    func markWatched(_ videoID: String) {
        guard !videoID.isEmpty else { return }
        let hadResumePoint = points.removeValue(forKey: videoID) != nil
        guard hadResumePoint || watched[videoID] == nil else { return }
        watched[videoID] = Date()
        watched = Self.trimmedWatched(watched)
        save()
    }

    func clear(videoID: String) {
        guard points.removeValue(forKey: videoID) != nil else { return }
        save()
    }
    func clearContinueWatching() {
        guard !points.isEmpty else { return }
        points = [:]
        save()
    }
    nonisolated static func outcome(position: TimeInterval, duration: TimeInterval) -> VideoWatchOutcome {
        guard position >= minimumPosition else { return .discard }
        guard duration > 0 else { return .resume }
        return position < duration - completionTail ? .resume : .watched
    }
    nonisolated static func trimmed(_ points: [String: VideoResumePoint]) -> [String: VideoResumePoint] {
        guard points.count > entryLimit else { return points }
        let keep = points.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(entryLimit)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }
    nonisolated static func trimmedWatched(_ watched: [String: Date]) -> [String: Date] {
        guard watched.count > watchedLimit else { return watched }
        let keep = watched
            .sorted { $0.value > $1.value }
            .prefix(watchedLimit)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    // MARK: - Account scoping

    /// Reads storage rather than an `AuthManager` instance because `AccountView`
    /// mints a fresh one per visit, so there is no instance to hold on to.
    private static func currentAccount() -> String? {
        accountIdentity(for: AuthManager.persistedDescriptor())
    }

    nonisolated static func accountIdentity(for descriptor: WatchSessionLink.Descriptor?) -> String? {
        guard let descriptor else { return nil }
        guard descriptor.isSignedIn else { return "guest" }
        let identity = descriptor.userID ?? descriptor.username
        guard let identity, !identity.isEmpty else { return "guest" }
        return identity
    }
    private func rebindAccount() {
        guard let account = Self.currentAccount() else { return }
        guard account != self.account else { return }
        self.account = account
        load()
    }
    private var storageKey: String {
        "nk.videoResume.v1." + SongStorageKey.component(for: account ?? "unavailable")
    }

    private var watchedStorageKey: String {
        "nk.videoWatched.v1." + SongStorageKey.component(for: account ?? "unavailable")
    }

    private func load() {
        guard account != nil else { return }
        points = (defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: VideoResumePoint].self, from: $0) })
            .map(Self.trimmed) ?? [:]
        watched = (defaults.data(forKey: watchedStorageKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) })
            .map(Self.trimmedWatched) ?? [:]
    }

    private func save() {
        guard isEnabled, account != nil else { return }
        if let data = try? JSONEncoder().encode(points) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(watched) {
            defaults.set(data, forKey: watchedStorageKey)
        }
    }
}
