import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Watch playback change detection")
struct PlaybackChangeDetectorTests {
    private func song(_ id: String, title: String = "Song") -> Song {
        Song(
            id: id,
            title: title,
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Artist"],
            coverArtists: nil,
            userUploaded: false
        )
    }

    private func state(song: Song?, queue: [Song], isPlaying: Bool = true) -> PlaybackChangeDetector.State {
        PlaybackChangeDetector.State(
            song: song, queue: queue, isPlaying: isPlaying, isRadio: false,
            isShuffled: false, repeatSetting: .off, error: nil,
            sleepDeadline: nil, sleepAtEndOfSong: false
        )
    }

    @Test("An unchanged state, including the same queue storage, is not a change")
    func unchangedStateIsNotAChange() {
        var detector = PlaybackChangeDetector()
        let queue = [song("a"), song("b")]
        let change1 = detector.changed(to: state(song: queue[0], queue: queue))
        #expect(change1)
        let change2 = detector.changed(to: state(song: queue[0], queue: queue))
        #expect(!change2)
    }

    /// `Song.==` compares ids, so a value comparison missed these.
    @Test("New metadata for a song that kept its id is a change")
    func sameIDMetadataIsAChange() {
        var detector = PlaybackChangeDetector()
        let queue = [song("a"), song("b")]
        _ = detector.changed(to: state(song: queue[0], queue: queue))
        let change3 = detector.changed(to: state(song: song("a", title: "Enriched"), queue: queue))
        #expect(change3)

        var requeued = queue
        requeued[1] = song("b", title: "Enriched")
        let change4 = detector.changed(to: state(song: song("a", title: "Enriched"), queue: requeued))
        #expect(change4)
    }

    @Test("A copied queue with the same contents is not a change")
    func copiedQueueWithSameContents() {
        var detector = PlaybackChangeDetector()
        let queue = [song("a"), song("b")]
        _ = detector.changed(to: state(song: queue[0], queue: queue))
        let rebuilt = queue.map { song($0.id) }
        let change5 = detector.changed(to: state(song: queue[0], queue: rebuilt))
        #expect(!change5)
    }

    @Test("Flags and reset count as changes")
    func flagsAndReset() {
        var detector = PlaybackChangeDetector()
        let queue = [song("a")]
        _ = detector.changed(to: state(song: queue[0], queue: queue))
        let change6 = detector.changed(to: state(song: queue[0], queue: queue, isPlaying: false))
        #expect(change6)
        detector.reset()
        let change7 = detector.changed(to: state(song: queue[0], queue: queue, isPlaying: false))
        #expect(change7)
    }
}
