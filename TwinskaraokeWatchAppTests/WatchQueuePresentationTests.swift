import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch queue presentation")
struct WatchQueuePresentationTests {
    @Test("Duplicate song ids keep unique queue entries and select the tapped occurrence")
    func duplicateQueueEntriesRemainDistinct() throws {
        let manager = AudioManager { _ in
            try await Task.sleep(for: .seconds(3_600))
            throw CancellationError()
        }
        let first = makeSong(id: "duplicate", title: "First Copy")
        let middle = makeSong(id: "middle", title: "Middle")
        let second = makeSong(id: "duplicate", title: "Second Copy")

        manager.play(song: first, context: [first, middle, second])

        #expect(manager.upNextQueueEntries.map(\.id) == [1, 2])
        #expect(Set(manager.upNextQueueEntries.map(\.id)).count == 2)
        #expect(manager.playQueueItem(at: 2))
        #expect(manager.currentIndex == 2)
        #expect(manager.currentSong?.title == "Second Copy")
        #expect(manager.queue.map(\.title) == ["First Copy", "Middle", "Second Copy"])
    }

    @Test("Repeat all reports its continuation at the end of the queue")
    func repeatAllEndTextMatchesPlayback() {
        #expect(
            WatchQueuePresentation.summary(
                upNextSongs: [],
                queueCount: 3,
                playbackMode: .listLoop
            ) == "Repeats from beginning"
        )
        #expect(
            WatchQueuePresentation.emptyState(
                queueCount: 3,
                playbackMode: .listLoop
            ).title == "Repeating Queue"
        )
        #expect(
            WatchQueuePresentation.accessibilityValue(
                upNextCount: 0,
                queueCount: 3,
                playbackMode: .listLoop
            ) == "Queue repeats from beginning"
        )
    }

    @Test("Repeat one reports the current song as the continuation")
    func repeatOneEndTextMatchesPlayback() {
        #expect(
            WatchQueuePresentation.summary(
                upNextSongs: [],
                queueCount: 3,
                playbackMode: .singleLoop
            ) == "Repeats this song"
        )
        #expect(
            WatchQueuePresentation.emptyState(
                queueCount: 3,
                playbackMode: .singleLoop
            ).title == "Repeat One"
        )
        #expect(
            WatchQueuePresentation.accessibilityValue(
                upNextCount: 0,
                queueCount: 3,
                playbackMode: .singleLoop
            ) == "Current song repeats"
        )
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            duration: 180,
            absolutePath: "/audio/\(id).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
    }
}
