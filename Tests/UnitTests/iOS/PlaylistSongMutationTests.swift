import Testing
@testable import Twinskaraoke

@MainActor
struct PlaylistSongMutationTests {
    /// Identical requests share success or failure without suppressing later intentional actions.
    @Test func concurrentIdenticalMutationsShareOneResult() {
        for adding in [true, false] {
            let coordinator = PlaylistSongMutationCoordinator()
            let key = PlaylistSongMutationCoordinator.Key(playlistID: "playlist", songID: "song", adding: adding)
            var results: [Bool] = []
            #expect(coordinator.begin(key) { results.append($0) })
            #expect(!coordinator.begin(key) { results.append($0) })
            coordinator.finish(key, success: true)
            #expect(results == [true, true])
            // A completed mutation must not suppress a later intentional action.
            #expect(coordinator.begin(key) { results.append($0) })
            coordinator.finish(key, success: false)
            #expect(results == [true, true, false])
        }
    }

    /// Different playlists and mutation directions keep independent in-flight results.
    @Test func unrelatedMutationsRemainIndependent() {
        let coordinator = PlaylistSongMutationCoordinator()
        let add = PlaylistSongMutationCoordinator.Key(playlistID: "one", songID: "song", adding: true)
        let remove = PlaylistSongMutationCoordinator.Key(playlistID: "one", songID: "song", adding: false)
        let otherPlaylist = PlaylistSongMutationCoordinator.Key(playlistID: "two", songID: "song", adding: true)
        #expect(coordinator.begin(add, completion: nil))
        #expect(!coordinator.begin(add, completion: nil))
        #expect(coordinator.begin(remove, completion: nil))
        #expect(coordinator.begin(otherPlaylist, completion: nil))
        coordinator.finish(add, success: true)
        #expect(!coordinator.begin(otherPlaylist, completion: nil))
    }
}
