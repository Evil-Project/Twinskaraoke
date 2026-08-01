import Testing
@testable import Twinskaraoke

@Suite("Audio queue order")
struct AudioQueueOrderTests {
    @Test("Normalizing a context inserts the selected song without dropping the context")
    func normalizedQueueInsertsOutsideSong() {
        let selected = makeSong(id: "outside", title: "Outside")
        let context = [
            makeSong(id: "first", title: "First"),
            makeSong(id: "second", title: "Second"),
        ]

        let result = AudioPlayerManager.normalizedQueue(context, selected: selected)

        #expect(result == [selected] + context)
    }

    @Test("Shuffling keeps one selected entry first and preserves duplicates")
    func shuffledQueuePreservesDuplicates() {
        let selected = makeSong(id: "repeat", title: "Repeat")
        let duplicate = makeSong(id: "repeat", title: "Repeat Again")
        let other = makeSong(id: "other", title: "Other")
        let source = [selected, other, duplicate]

        let result = AudioPlayerManager.shuffledQueue(source, startingWith: selected)

        #expect(result.first == selected)
        #expect(result.count == source.count)
        #expect(result.count(where: { $0.id == selected.id }) == 2)
    }

    @Test("Next uses the tracked duplicate occurrence instead of the first matching ID")
    func nextUsesTrackedDuplicateOccurrence() throws {
        let firstDuplicate = makeSong(id: "repeat", title: "First Repeat")
        let middle = makeSong(id: "middle", title: "Middle")
        let secondDuplicate = makeSong(id: "repeat", title: "Second Repeat")
        let final = makeSong(id: "final", title: "Final")
        let queue = [firstDuplicate, middle, secondDuplicate, final]

        let selection = try #require(
            QueueOccurrenceNavigator.nextSelection(
                currentSong: secondDuplicate,
                currentIndex: 2,
                queue: queue,
                wrapsAtEnd: false
            )
        )

        #expect(selection.index == 3)
        #expect(selection.song.id == final.id)
    }

    @Test("Previous uses the tracked duplicate occurrence")
    func previousUsesTrackedDuplicateOccurrence() throws {
        let firstDuplicate = makeSong(id: "repeat", title: "First Repeat")
        let middle = makeSong(id: "middle", title: "Middle")
        let secondDuplicate = makeSong(id: "repeat", title: "Second Repeat")
        let queue = [firstDuplicate, middle, secondDuplicate]

        let selection = try #require(
            QueueOccurrenceNavigator.previousSelection(
                currentSong: secondDuplicate,
                currentIndex: 2,
                queue: queue
            )
        )

        #expect(selection.index == 1)
        #expect(selection.song.id == middle.id)
    }

    @Test("Repeat-all wraps only after the tracked final occurrence")
    func repeatAllWrapsAfterTrackedFinalOccurrence() throws {
        let first = makeSong(id: "repeat", title: "First Repeat")
        let middle = makeSong(id: "middle", title: "Middle")
        let finalDuplicate = makeSong(id: "repeat", title: "Final Repeat")
        let queue = [first, middle, finalDuplicate]

        let selection = try #require(
            QueueOccurrenceNavigator.nextSelection(
                currentSong: finalDuplicate,
                currentIndex: 2,
                queue: queue,
                wrapsAtEnd: true
            )
        )

        #expect(selection.index == 0)
        #expect(selection.song.title == first.title)
    }

    @Test("Direct selection prefers full song data before falling back to ID")
    func directSelectionPrefersExactSongData() {
        let first = makeSong(id: "repeat", title: "First Repeat")
        let second = makeSong(id: "repeat", title: "Second Repeat")
        let queue = [first, second]
        let idOnlyFallback = makeSong(id: "repeat", title: "Unknown Repeat")

        #expect(QueueOccurrenceNavigator.resolvedIndex(for: second, in: queue) == 1)
        #expect(QueueOccurrenceNavigator.resolvedIndex(for: idOnlyFallback, in: queue) == 0)
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Cover"],
            userUploaded: false
        )
    }
}
