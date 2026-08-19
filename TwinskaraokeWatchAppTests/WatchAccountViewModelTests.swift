import Testing
@testable import Twinskaraoke_Watch_App

@MainActor
@Suite("Watch account view models")
struct WatchAccountViewModelTests {
    @Test("A late favorites response cannot restore signed-out data")
    func favoritesResetRejectsLateResponse() async {
        let loader = SuspendedLoader<[Song]>()
        let viewModel = FavoritesViewModel(
            isAuthenticated: { true },
            loadSongs: { await loader.value() }
        )

        viewModel.fetch(force: true)
        await loader.waitUntilStarted()
        #expect(viewModel.isLoading)

        viewModel.reset()
        #expect(!viewModel.isLoading)
        #expect(viewModel.songs.isEmpty)

        await loader.resume(returning: [makeSong(id: "previous-account-favorite")])
        await settleTasks()

        #expect(viewModel.songs.isEmpty)
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test("A late playlist response cannot restore signed-out data")
    func playlistsResetRejectsLateResponse() async {
        let loader = SuspendedLoader<[Playlist]>()
        let viewModel = UserPlaylistsViewModel(
            isAuthenticated: { true },
            loadPlaylists: { await loader.value() }
        )

        viewModel.fetch(force: true)
        await loader.waitUntilStarted()
        #expect(viewModel.isLoading)

        viewModel.reset()
        #expect(!viewModel.isLoading)
        #expect(viewModel.playlists.isEmpty)

        await loader.resume(returning: [makePlaylist(id: "previous-account-playlist")])
        await settleTasks()

        #expect(viewModel.playlists.isEmpty)
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    private func makeSong(id: String) -> Song {
        UITestFixtures.song(id: id, title: id, artist: "Artist")
    }

    private func makePlaylist(id: String) -> Playlist {
        Playlist(
            id: id,
            name: id,
            songCount: 0,
            mosaicMedia: nil,
            songListDTOs: [],
            isPersonal: true
        )
    }

    private func settleTasks() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }
}

private actor SuspendedLoader<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var started = false

    func value() async -> Value {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func resume(returning value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
