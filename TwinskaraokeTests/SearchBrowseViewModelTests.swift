import Foundation
import Testing
@testable import Twinskaraoke

private enum SearchBrowseTestError: Error {
    case simulated
}

private actor RetryingPublicPlaylistsLoader {
    private(set) var requestCount = 0
    private let playlists: [Playlist]

    init(playlists: [Playlist]) {
        self.playlists = playlists
    }

    func load(startIndex _: Int, pageSize _: Int) async throws -> [Playlist] {
        requestCount += 1
        if requestCount == 1 {
            throw SearchBrowseTestError.simulated
        }
        return playlists
    }
}

private actor RetryingTopChartLoader {
    private(set) var allTimeRequestCount = 0
    private let songs: [Song]

    init(songs: [Song]) {
        self.songs = songs
    }

    func loadAllTime() async throws -> [Song] {
        allTimeRequestCount += 1
        if allTimeRequestCount == 1 {
            throw SearchBrowseTestError.simulated
        }
        return songs
    }

    func loadWeekly() async throws -> [Song] {
        songs
    }
}

@MainActor
@Suite("Search browse retry")
struct SearchBrowseViewModelTests {
    @Test("Public playlists can retry after a transient initial failure")
    func publicPlaylistsRetryAfterFailure() async {
        let expected = [Self.playlist(id: "retry-playlist")]
        let loader = RetryingPublicPlaylistsLoader(playlists: expected)
        let viewModel = PublicPlaylistsViewModel { startIndex, pageSize in
            try await loader.load(startIndex: startIndex, pageSize: pageSize)
        }

        let firstLoad = viewModel.loadIfNeeded()
        await firstLoad?.value

        #expect(viewModel.playlists.isEmpty)
        #expect(viewModel.loadFailed)
        #expect(!viewModel.isLoading)

        let retry = viewModel.retry()
        await retry?.value

        #expect(viewModel.playlists.map(\.id) == expected.map(\.id))
        #expect(!viewModel.loadFailed)
        #expect(await loader.requestCount == 2)
    }

    @Test("Top chart can retry after a transient initial failure")
    func topChartRetryAfterFailure() async {
        let expected = [Self.song(id: "retry-song")]
        let loader = RetryingTopChartLoader(songs: expected)
        let viewModel = TopChartViewModel(
            allTimeLoader: { try await loader.loadAllTime() },
            weeklyLoader: { try await loader.loadWeekly() }
        )

        let firstLoad = viewModel.loadIfNeeded()
        await firstLoad?.value

        #expect(viewModel.songs.isEmpty)
        #expect(viewModel.loadFailed)
        #expect(!viewModel.isLoading)

        let retry = viewModel.retry()
        await retry?.value

        #expect(viewModel.songs.map(\.id) == expected.map(\.id))
        #expect(viewModel.weeklyTrending.map(\.id) == expected.map(\.id))
        #expect(!viewModel.loadFailed)
        #expect(await loader.allTimeRequestCount == 2)
    }

    private static func playlist(id: String) -> Playlist {
        Playlist(
            id: id,
            name: "Retry Playlist",
            songCount: 0,
            mosaicMedia: nil,
            songListDTOs: nil
        )
    }

    private static func song(id: String) -> Song {
        Song(
            id: id,
            title: "Retry Song",
            duration: 180,
            absolutePath: "audio/\(id).mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Test Artist"],
            coverArtists: nil,
            userUploaded: false
        )
    }
}
