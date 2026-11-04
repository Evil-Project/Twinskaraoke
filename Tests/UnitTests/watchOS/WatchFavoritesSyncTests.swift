import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Companion favorites refresh")
@MainActor
struct WatchFavoritesSyncTests {
    @Test("Successful star commits once and the companion refresh reads new server membership")
    func successfulSync() async {
        let song = UITestFixtures.song(id: "starred", title: "Starred", artist: "Artist")
        var server: [Song] = []
        var writes = 0
        let watch = FavoritesManager(authenticated: { true }, fetchSongs: { server }, setFavorite: { _, favorite in
            writes += 1
            server = favorite ? [song] : []
            return true
        })
        let phone = FavoritesManager(authenticated: { true }, fetchSongs: { server }, setFavorite: { _, _ in
            Issue.record("Refreshing favorites must not write a toggle")
            return false
        })
        await phone.refreshFromCompanion()
        #expect(!phone.isFavorite(song.id))
        await watch.toggle(songID: song.id)?.value
        #expect(watch.isFavorite(song.id))
        await phone.refreshFromCompanion()
        #expect(phone.isFavorite(song.id))
        #expect(writes == 1)
    }

    @Test("Unstarring on the watch removes the song for the companion refresh")
    func unstarSync() async {
        let song = UITestFixtures.song(id: "starred", title: "Starred", artist: "Artist")
        var server: [Song] = [song]
        let watch = FavoritesManager(authenticated: { true }, fetchSongs: { server }, setFavorite: { _, favorite in
            server = favorite ? [song] : []
            return true
        })
        let phone = FavoritesManager(authenticated: { true }, fetchSongs: { server }, setFavorite: { _, _ in
            Issue.record("Refreshing favorites must not write a toggle")
            return false
        })
        await watch.refreshFromCompanion()
        await phone.refreshFromCompanion()
        #expect(watch.isFavorite(song.id))
        #expect(phone.isFavorite(song.id))

        await watch.toggle(songID: song.id)?.value
        #expect(!watch.isFavorite(song.id))
        #expect(server.isEmpty)
        await phone.refreshFromCompanion()
        #expect(!phone.isFavorite(song.id))
    }

    @Test("Failed star saves restore the previous membership")
    func failedSave() async {
        let manager = FavoritesManager(authenticated: { true }, fetchSongs: { [] }, setFavorite: { _, _ in false })
        await manager.toggle(songID: "song")?.value
        #expect(!manager.isFavorite("song"))
    }

    @Test("An account clear during an old save cannot add the old account's favorite")
    func accountChangesDuringSave() async {
        let reference = ManagerReference()
        let manager = FavoritesManager(authenticated: { true }, fetchSongs: { [] }, setFavorite: { _, _ in
            reference.manager?.clear()
            return true
        })
        reference.manager = manager
        await manager.toggle(songID: "old-account-song")?.value
        #expect(manager.favoriteIDs.isEmpty)
    }
}

@MainActor
private final class ManagerReference {
    weak var manager: FavoritesManager?
}
