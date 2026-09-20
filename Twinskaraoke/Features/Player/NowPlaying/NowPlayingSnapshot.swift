import Observation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif
@MainActor
@Observable
final class NowPlayingSnapshotState {
    static let shared = NowPlayingSnapshotState()

    var hasCurrentSong: Bool {
        snapshot.id != nil
    }

    var id: String {
        snapshot.id ?? "now-playing"
    }

    var title: String {
        snapshot.title
    }

    var subtitle: String {
        snapshot.subtitle
    }

    var artwork: UIImage? {
        #if DEBUG
        if PlayerClosingTestArtwork.enabled, hasCurrentSong { return PlayerClosingTestArtwork.image }
        #endif
        return snapshot.artwork
    }

    var isPlaying: Bool {
        snapshot.isPlaying
    }

    var isRadioMode: Bool {
        snapshot.isRadioMode
    }

    /// Set while the current song has failed to load; shown in place of the
    /// artist so the bar says why it is sitting paused.
    var failureMessage: String? {
        snapshot.failureMessage
    }

    private var snapshot = NowPlayingSnapshot()
    @ObservationIgnored private var pendingSnapshot = NowPlayingSnapshot()
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var observation: ObservationToken?

    private init() {
        observation = observeContinuously({
            let manager = AudioPlayerManager.shared
            _ = manager.currentSong
            _ = manager.nowPlayingArtwork
            _ = manager.isPlaying
            _ = manager.isRadioMode
            _ = manager.loadFailure
        }, onChange: { [weak self] in
            self?.rebuildPendingSnapshot()
        })
        rebuildPendingSnapshot()
    }

    private func rebuildPendingSnapshot() {
        let manager = AudioPlayerManager.shared
        let song = manager.currentSong
        pendingSnapshot.id = song?.id
        pendingSnapshot.title = song?.title ?? ""
        pendingSnapshot.subtitle = song?.displayArtist ?? ""
        pendingSnapshot.artwork = manager.nowPlayingArtwork
        pendingSnapshot.isPlaying = manager.isPlaying
        pendingSnapshot.isRadioMode = manager.isRadioMode
        pendingSnapshot.failureMessage = manager.loadFailure?.message
        scheduleSnapshotPublish()
    }

    private func scheduleSnapshotPublish() {
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard let self else { return }
            let nextSnapshot = pendingSnapshot
            publishTask = nil
            guard !snapshot.matches(nextSnapshot) else { return }

            snapshot = nextSnapshot
        }
    }
}

private struct NowPlayingSnapshot {
    var id: String?
    var title = ""
    var subtitle = ""
    var artwork: UIImage?
    var isPlaying = false
    var isRadioMode = false
    var failureMessage: String?

    func matches(_ other: NowPlayingSnapshot) -> Bool {
        id == other.id
            && title == other.title
            && subtitle == other.subtitle
            && artwork === other.artwork
            && isPlaying == other.isPlaying
            && isRadioMode == other.isRadioMode
            && failureMessage == other.failureMessage
    }
}
