import Foundation
import Testing
@testable import Twinskaraoke

/// Stands in for the Library overview's requests. Each favourites request
/// takes the next queued result; the last one repeats.
@MainActor
private final class FakeLibraryService {
    var favoriteSongsResults: [Result<[Song], any Error>] = [.success([])]
    var playlistsResult: Result<[Playlist], any Error> = .success([])
    private(set) var favoriteSongsCalls = 0

    var service: PlaylistsViewModel.Service {
        PlaylistsViewModel.Service(
            playlists: { try self.playlistsResult.get() },
            favoriteSongs: {
                let index = min(self.favoriteSongsCalls, self.favoriteSongsResults.count - 1)
                self.favoriteSongsCalls += 1
                return try self.favoriteSongsResults[index].get()
            }
        )
    }
}

@MainActor
struct PlaylistsViewModelTests {
    private func settle(_ model: PlaylistsViewModel) async {
        while model.isLoading || model.isLoadingFavorites { await Task.yield() }
    }

    private let song = UITestFixtures.song(id: "a", title: "A", artist: "B")

    /// App activation invalidates the shared favourites request, which
    /// cancels it under the Library's load.
    @Test func aSupersededFavouritesRequestIsAskedForAgain() async {
        let fake = FakeLibraryService()
        fake.favoriteSongsResults = [.failure(URLError(.cancelled)), .success([song])]
        let model = PlaylistsViewModel(service: fake.service)

        model.fetchFavoriteSongs()
        await settle(model)

        #expect(model.favoritesErrorMessage == nil)
        #expect(model.favoriteSongs == [song])
        #expect(fake.favoriteSongsCalls == 2)
    }

    @Test func aCancelledLoadIsNotAnError() async {
        let fake = FakeLibraryService()
        fake.favoriteSongsResults = [.failure(CancellationError())]
        fake.playlistsResult = .failure(URLError(.cancelled))
        let model = PlaylistsViewModel(service: fake.service)

        model.fetchFavoriteSongs()
        model.fetchPlaylists()
        await settle(model)

        #expect(model.favoritesErrorMessage == nil)
        #expect(model.errorMessage == nil)
        #expect(fake.favoriteSongsCalls == 2)

        // Still unloaded, so the next appearance asks again.
        fake.favoriteSongsResults = [.success([song])]
        model.fetchFavoriteSongs()
        await settle(model)
        #expect(model.favoriteSongs == [song])
    }

    @Test func aFailedLoadReportsAnErrorAndARetryClearsIt() async {
        let fake = FakeLibraryService()
        fake.favoriteSongsResults = [.failure(URLError(.badServerResponse))]
        fake.playlistsResult = .failure(URLError(.notConnectedToInternet))
        let model = PlaylistsViewModel(service: fake.service)

        model.fetchFavoriteSongs()
        model.fetchPlaylists()
        await settle(model)
        #expect(model.favoritesErrorMessage != nil)
        #expect(model.errorMessage != nil)
        #expect(fake.favoriteSongsCalls == 1)

        fake.favoriteSongsResults = [.success([])]
        fake.playlistsResult = .success([])
        model.fetchFavoriteSongs()
        model.fetchPlaylists()
        await settle(model)
        #expect(model.favoritesErrorMessage == nil)
        #expect(model.errorMessage == nil)
    }
}
