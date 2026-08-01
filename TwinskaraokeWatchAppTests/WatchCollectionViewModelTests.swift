import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

private enum WatchCollectionLoaderFailure: Error {
    case simulated
}

private actor ControlledWatchCollectionLoader<Value: Sendable> {
    private var continuations: [Int: CheckedContinuation<Value, Error>] = [:]
    private var nextRequest = 0

    func load() async throws -> Value {
        let request = nextRequest
        nextRequest += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[request] = continuation
        }
    }

    func waitUntilRegistered(_ request: Int) async {
        while continuations[request] == nil {
            await Task.yield()
        }
    }

    func succeed(_ request: Int, with value: Value) {
        continuations.removeValue(forKey: request)?.resume(returning: value)
    }

    func fail(_ request: Int) {
        continuations.removeValue(forKey: request)?.resume(
            throwing: WatchCollectionLoaderFailure.simulated
        )
    }
}

@MainActor
@Suite("Watch collection loading state")
struct WatchCollectionViewModelTests {
    @Test("A failed songs request can recover through retry")
    func failedRequestCanRetrySuccessfully() async {
        let loader = ControlledWatchCollectionLoader<[Song]>()
        let viewModel = SongsViewModel {
            try await loader.load()
        }

        viewModel.fetchSongs()
        await loader.waitUntilRegistered(0)
        await loader.fail(0)
        for _ in 0 ..< 1_000 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.songs.isEmpty)
        #expect(viewModel.loadErrorMessage != nil)

        viewModel.fetchSongs(force: true)
        await loader.waitUntilRegistered(1)
        await loader.succeed(1, with: [makeSong(id: "recovered")])
        for _ in 0 ..< 1_000 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.songs.map(\.id) == ["recovered"])
        #expect(viewModel.loadErrorMessage == nil)
    }

    @Test("A stale response cannot replace a forced Home retry")
    func staleResponseIsIgnoredAfterForcedRetry() async {
        let loader = ControlledWatchCollectionLoader<[Song]>()
        let viewModel = HomeViewModel {
            try await loader.load()
        }

        viewModel.fetchTrending()
        await loader.waitUntilRegistered(0)
        viewModel.fetchTrending(force: true)
        await loader.waitUntilRegistered(1)

        await loader.succeed(0, with: [makeSong(id: "stale")])
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        #expect(viewModel.isLoading)
        #expect(viewModel.trending.isEmpty)
        #expect(viewModel.loadErrorMessage == nil)

        await loader.succeed(1, with: [makeSong(id: "current")])
        for _ in 0 ..< 1_000 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.trending.map(\.id) == ["current"])
        #expect(viewModel.loadErrorMessage == nil)
    }

    @Test("Every watch collection model exposes request failure")
    func allCollectionModelsExposeFailure() async {
        let homeLoader = ControlledWatchCollectionLoader<[Song]>()
        let songsLoader = ControlledWatchCollectionLoader<[Song]>()
        let playlistsLoader = ControlledWatchCollectionLoader<[Playlist]>()
        let detailLoader = ControlledWatchCollectionLoader<[Song]>()
        let home = HomeViewModel { try await homeLoader.load() }
        let songs = SongsViewModel { try await songsLoader.load() }
        let playlists = PlaylistsViewModel { try await playlistsLoader.load() }
        let detail = PlaylistDetailViewModel(playlistID: "playlist") { _ in
            try await detailLoader.load()
        }

        home.fetchTrending()
        songs.fetchSongs()
        playlists.fetchMusic()
        detail.fetchSongs()
        await homeLoader.waitUntilRegistered(0)
        await songsLoader.waitUntilRegistered(0)
        await playlistsLoader.waitUntilRegistered(0)
        await detailLoader.waitUntilRegistered(0)

        await homeLoader.fail(0)
        await songsLoader.fail(0)
        await playlistsLoader.fail(0)
        await detailLoader.fail(0)
        for _ in 0 ..< 1_000
            where home.isLoading || songs.isLoading || playlists.isLoading || detail.isLoading
        {
            await Task.yield()
        }

        #expect(home.loadErrorMessage != nil)
        #expect(songs.loadErrorMessage != nil)
        #expect(playlists.loadErrorMessage != nil)
        #expect(detail.loadErrorMessage != nil)
        #expect(!home.isLoading)
        #expect(!songs.isLoading)
        #expect(!playlists.isLoading)
        #expect(!detail.isLoading)
    }

    @Test("A successful empty playlist remains a legitimate empty state")
    func successfulEmptyResponseHasNoError() async {
        let viewModel = PlaylistDetailViewModel(playlistID: "empty") { _ in [] }

        viewModel.fetchSongs()
        for _ in 0 ..< 1_000 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(!viewModel.isLoading)
        #expect(viewModel.songs.isEmpty)
        #expect(viewModel.loadErrorMessage == nil)
    }

    private func makeSong(id: String) -> Song {
        Song(
            id: id,
            title: id,
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
