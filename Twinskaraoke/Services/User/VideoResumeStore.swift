import Foundation
import Observation

/// How far into a video the viewer got, kept so it can be resumed later.
///
/// Carries the `GalleryVideo` rather than just its ID so the Continue Watching
/// shelf can render without the catalogue: `/api/videos` pages 25 at a time
/// through ~1400 items, so a video watched last month is almost never among the
/// pages currently loaded.
nonisolated struct VideoResumePoint: Codable, Equatable, Sendable, Identifiable {
    let video: GalleryVideo
    /// Seconds from the start.
    let position: TimeInterval
    /// Runtime as the *player* measured it, or 0 when it was never established.
    ///
    /// Deliberately not `GalleryVideo.duration`, which is 0 or absent for ~1279
    /// of the ~1385 catalogue items and is never set for the watchalongs.
    let duration: TimeInterval
    let updatedAt: Date

    var id: String { video.id }

    /// Fraction watched, or `nil` when the runtime was never established — in
    /// which case callers must omit the progress bar rather than draw an empty
    /// one, because "unknown" and "just started" are not the same thing.
    var fraction: Double? {
        guard duration > 0 else { return nil }
        return min(1, max(0, position / duration))
    }

    /// Time left, or `nil` when the runtime was never established.
    var remaining: TimeInterval? {
        guard duration > 0 else { return nil }
        return max(0, duration - position)
    }
}

/// What a reported playhead position means for the video it came from.
nonisolated enum VideoWatchOutcome: Equatable, Sendable {
    /// Far enough in, and far enough from the end, to be worth returning to.
    case resume
    /// Close enough to the end to count as finished.
    case watched
    /// Too near the start to be worth remembering at all.
    case discard
}

/// Where the viewer left off in each gallery video, and which they finished.
///
/// Local by necessity: the neurokaraoke API has no watch-position endpoint, and
/// neither does its own web client — `Components.VideoPlayer` there never even
/// reads `currentTime`, and `VideoDTO` carries no position field. Pillarbox has
/// a `ResumeState`, but it is internal and only restores a position when an item
/// is rebuilt inside one session, so persistence has to live here.
///
/// **Scoped to the signed-in account.** Positions are keyed by user ID, so two
/// people sharing a device never see each other's history and signing back in
/// restores your own. Signed-out viewing accumulates in its own `guest` bucket
/// rather than being discarded, which keeps the feature working before sign-in
/// without ever mixing the two.
@MainActor
@Observable
final class VideoResumeStore {
    static let shared = VideoResumeStore()

    /// Below this, a position is not worth resuming from — opening a video and
    /// immediately leaving should not litter Continue Watching.
    nonisolated static let minimumPosition: TimeInterval = 10

    /// With less than this left, the video counts as watched: the entry is
    /// dropped so a re-open starts from the beginning instead of the credits.
    nonisolated static let completionTail: TimeInterval = 10

    /// Enough for a personal history, small enough that the whole map stays
    /// cheap to re-encode on the save cadence. Entries hold a full
    /// `GalleryVideo`, so this is roughly 40 KB rather than a few hundred bytes.
    nonisolated static let entryLimit = 60

    /// Far higher than `entryLimit` because a completion is an ID and a date,
    /// not a whole video, and because finished videos accumulate much faster
    /// than half-finished ones.
    nonisolated static let watchedLimit = 500

    /// Videos with somewhere to return to.
    private(set) var points: [String: VideoResumePoint] = [:]

    /// Videos watched to the end, and when.
    ///
    /// Held apart from `points` rather than as a flag on one: a finished video
    /// has no position to return to, only an ID, and letting completions share
    /// the resume map's budget would evict videos the viewer is still partway
    /// through. The two are mutually exclusive — see `markWatched`.
    private(set) var watched: [String: Date] = [:]

    /// Most recently watched first — the order the shelf presents.
    var continueWatching: [VideoResumePoint] {
        points.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var account: String
    private var sessionObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    /// Watch history is device state that outlives a launch, so a UI test would
    /// inherit whatever the previous run played and see a different gallery.
    /// Kept empty there, the same way `RecentlyPlayedStore` is on the watch.
    private let isEnabled = !AppRuntime.isUITestMode

    private init() {
        account = Self.currentAccount()
        guard isEnabled else { return }
        load()
        sessionObserver = NotificationCenter.default.addObserver(
            forName: WatchSessionLink.sessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebindAccount()
            }
        }
    }

    isolated deinit {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
    }

    // MARK: - Reading

    /// Where to resume `videoID`, or `nil` if there is nowhere to return to.
    ///
    /// A video that has been watched has no resume point by construction, so
    /// re-opening one starts it from the beginning.
    func point(for videoID: String) -> VideoResumePoint? {
        points[videoID]
    }

    func isWatched(_ videoID: String) -> Bool {
        watched[videoID] != nil
    }

    // MARK: - Writing

    /// Records the playhead, promoting the video to watched or forgetting it
    /// entirely when the position no longer describes somewhere to return to.
    ///
    /// Callers must only report positions the player has actually reached —
    /// see `VideoPlaybackModel.persistPosition()`. A position sampled before a
    /// resume seek lands reads as zero and would clear the very entry that seek
    /// is about to use.
    func record(_ video: GalleryVideo, position: TimeInterval, duration: TimeInterval) {
        guard isEnabled, !video.id.isEmpty, position.isFinite, position >= 0 else { return }
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
            // Re-watching supersedes having watched: the card goes back to
            // showing a progress bar, and back onto the shelf.
            watched[video.id] = nil
            save()
        }
    }

    /// Marks a video as watched to the end.
    ///
    /// The two maps are mutually exclusive — a finished video has no position
    /// to return to — so this also takes it off the Continue Watching shelf.
    func markWatched(_ videoID: String) {
        guard isEnabled, !videoID.isEmpty else { return }
        let hadResumePoint = points.removeValue(forKey: videoID) != nil
        // Already watched and nothing else changed: don't rewrite storage on
        // every `.ended` the player publishes.
        guard hadResumePoint || watched[videoID] == nil else { return }
        watched[videoID] = Date()
        watched = Self.trimmedWatched(watched)
        save()
    }

    func clear(videoID: String) {
        guard points.removeValue(forKey: videoID) != nil else { return }
        save()
    }

    /// Empties the Continue Watching shelf.
    ///
    /// Deliberately leaves the watched history alone: the shelf's own menu is
    /// offering to clear the shelf, not to forget everything ever finished.
    func clearContinueWatching() {
        guard !points.isEmpty else { return }
        points = [:]
        save()
    }

    /// What a reported position means for a video.
    ///
    /// `duration` of 0 means the runtime was never established, in which case
    /// completion cannot be judged and only the floor applies.
    nonisolated static func outcome(position: TimeInterval, duration: TimeInterval) -> VideoWatchOutcome {
        // Scrubbed back to the top, or barely started: nothing to return to.
        guard position >= minimumPosition else { return .discard }
        guard duration > 0 else { return .resume }
        // Note this also makes every position in a clip shorter than
        // `minimumPosition + completionTail` resolve to `.discard` or
        // `.watched`, never `.resume`, which is intended: there is no span in a
        // 15-second clip both far enough in to be worth resuming and far enough
        // from the end not to count as finished.
        return position < duration - completionTail ? .resume : .watched
    }

    /// Drops the oldest entries once the map outgrows `entryLimit`.
    nonisolated static func trimmed(_ points: [String: VideoResumePoint]) -> [String: VideoResumePoint] {
        guard points.count > entryLimit else { return points }
        let keep = points.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(entryLimit)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }

    /// The same, for the watched map.
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
    private static func currentAccount() -> String {
        let descriptor = AuthManager.persistedDescriptor()
        guard descriptor.isSignedIn else { return "guest" }
        let identity = descriptor.userID ?? descriptor.username
        guard let identity, !identity.isEmpty else { return "guest" }
        return identity
    }

    /// Swaps buckets after a sign-in, sign-out or account switch.
    ///
    /// Nothing is written on the way out: every mutation already persisted
    /// immediately, and writing here would post the outgoing account's map to
    /// whichever key is current by the time it ran.
    private func rebindAccount() {
        let account = Self.currentAccount()
        guard account != self.account else { return }
        self.account = account
        load()
    }

    // MARK: - Persistence

    /// Two keys rather than one envelope, so the maps stay independently
    /// readable and adding the watched history needed no migration of resume
    /// points already on device.
    private var storageKey: String {
        "nk.videoResume.v1." + SongStorageKey.component(for: account)
    }

    private var watchedStorageKey: String {
        "nk.videoWatched.v1." + SongStorageKey.component(for: account)
    }

    private func load() {
        points = (defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: VideoResumePoint].self, from: $0) })
            .map(Self.trimmed) ?? [:]
        watched = (defaults.data(forKey: watchedStorageKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) })
            .map(Self.trimmedWatched) ?? [:]
    }

    private func save() {
        guard isEnabled else { return }
        if let data = try? JSONEncoder().encode(points) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(watched) {
            defaults.set(data, forKey: watchedStorageKey)
        }
    }
}
