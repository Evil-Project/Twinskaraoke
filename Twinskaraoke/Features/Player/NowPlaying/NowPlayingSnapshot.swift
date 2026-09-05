import Observation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// A coalesced view of `AudioPlayerManager` for the mini player to read.
///
/// The bar is on screen for most of a session and sits above every scroll view
/// in the app, so it must not rebuild on every tick of the underlying manager.
/// This collects the four fields the bar actually shows, republishes them at
/// most once per frame-and-a-bit, and drops any rebuild that produced the same
/// values — which is why the per-property `removeDuplicates` this replaced is
/// not needed: an identical snapshot never reaches the property that observers
/// are watching.
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

    func matches(_ other: NowPlayingSnapshot) -> Bool {
        id == other.id
            && title == other.title
            && subtitle == other.subtitle
            && artwork === other.artwork
            && isPlaying == other.isPlaying
            && isRadioMode == other.isRadioMode
    }
}
