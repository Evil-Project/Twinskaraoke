import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Uploaded songs")
struct UploadedSongsViewModelTests {
    @Test("Duplicate uploaded songs retain API order")
    func duplicateSongsRetainAPIOrder() {
        let first = song(id: "first", title: "First")
        let duplicate = song(id: "first", title: "Duplicate")
        let second = song(id: "second", title: "Second")

        let songs = UploadedSongsViewModel.removingDuplicateSongs([first, duplicate, second])

        #expect(songs.map(\.id) == ["first", "second"])
        #expect(songs.first?.title == "First")
    }

    @Test("Task and URL cancellations use the cancellation path")
    func cancellationErrorsUseCancellationPath() {
        #expect(UploadedSongsViewModel.isCancellationError(CancellationError()))
        #expect(UploadedSongsViewModel.isCancellationError(URLError(.cancelled)))
        #expect(!UploadedSongsViewModel.isCancellationError(URLError(.timedOut)))
    }

    @Test("Resolved durations fill only missing values")
    func resolvedDurationsFillOnlyMissingValues() {
        let missingDuration = song(id: "missing", title: "Missing", duration: 0)
        let existingDuration = song(id: "existing", title: "Existing", duration: 90)

        let songs = UploadedSongDurationResolver.applyingResolvedDurations(
            ["missing": 214, "existing": 999],
            to: [missingDuration, existingDuration]
        )

        #expect(songs.map(\.id) == ["missing", "existing"])
        #expect(songs.map(\.duration) == [214, 90])
        #expect(songs[0].absolutePath == missingDuration.absolutePath)
        #expect(songs[0].userUploaded == true)
    }

    @Test("Cached durations apply to sparse playlist songs")
    func cachedDurationsApplyToSparsePlaylistSongs() async {
        let resolver = UploadedSongDurationResolver()
        let completeSong = song(id: "upload", title: "Upload", duration: 214)
        _ = await resolver.fillingMissingDurations(in: [completeSong])

        let sparsePlaylistSong = song(
            id: "upload",
            title: "Upload",
            duration: 0,
            includesAudioPath: false
        )
        let songs = await resolver.fillingMissingDurations(in: [sparsePlaylistSong])

        #expect(songs.first?.duration == 214)
    }

    @Test("Local downloaded audio is preferred for duration lookup")
    func localDownloadedAudioIsPreferredForDurationLookup() {
        let uploadedSong = song(id: "upload", title: "Upload", duration: 0)
        let localURL = URL(fileURLWithPath: "/tmp/upload.m4a")

        let sourceURL = UploadedSongDurationResolver.preferredAudioURL(
            for: uploadedSong,
            localAudioURLs: [uploadedSong.id: localURL]
        )

        #expect(sourceURL == localURL)
    }

    private func song(
        id: String,
        title: String,
        duration: Int = 120,
        includesAudioPath: Bool = true
    ) -> Song {
        Song(
            id: id,
            title: title,
            duration: duration,
            absolutePath: includesAudioPath ? "uploads/\(id).m4a" : nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true
        )
    }
}
