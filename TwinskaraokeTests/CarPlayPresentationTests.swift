import CarPlay
import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("CarPlay presentation", .serialized)
struct CarPlayPresentationTests {
    @Test("Failed root refreshes show a notice alongside retained rows")
    func retainedRootFailureNotices() {
        let delegate = CarPlaySceneDelegate()
        let playlist = Playlist(id: "cached", name: "Cached playlist", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        delegate.serverPlaylists = [playlist]
        delegate.latestSongs = fixtures(30)
        delegate.randomSongs = fixtures(30)
        delegate.loadStates = ["playlists": .failed, "latest": .failed, "random": .failed]
        let library = CPListTemplate(title: "Library", sections: [])
        let latest = CPListTemplate(title: "New", sections: [])
        let random = CPListTemplate(title: "Random", sections: [])
        delegate.playlistsTemplate = library
        delegate.latestTemplate = latest
        delegate.randomTemplate = random
        delegate.rebuildPlaylistsTemplate()
        delegate.rebuildLatestTemplate()
        delegate.rebuildRandomTemplate()
        for template in [library, latest, random] {
            #expect(texts(template).first == "Couldn't Refresh")
            #expect(template.itemCount <= CPListTemplate.maximumItemCount)
        }
        #expect(texts(library).contains("Cached playlist"))
        #expect(texts(latest).contains("Song 0"))
        #expect(texts(random).contains("Song 0"))
        delegate.serverPlaylists = []
        delegate.rebuildPlaylistsTemplate()
        #expect(texts(library).first == "Couldn't Refresh")
        #expect(texts(library).contains("Favourite Songs"))
    }

    @Test("An empty server playlist cannot regain removed inline songs on a failed reload")
    func authoritativeEmptyPlaylist() async throws {
        let delegate = CarPlaySceneDelegate()
        let playlist = Playlist(id: "emptied", name: "Emptied", songCount: 2, mosaicMedia: nil, songListDTOs: fixtures(2))
        let template = CPListTemplate(title: "Emptied", sections: [])
        delegate.fetchPlaylistSongs = { _ in [] }
        delegate.loadPlaylistSongs(for: playlist, into: template)
        let first = try #require(delegate.playlistLoadTasks[playlist.id])
        await first.value
        #expect(delegate.openPlaylistSongs[playlist.id]?.isEmpty == true)
        delegate.fetchPlaylistSongs = { _ in throw URLError(.notConnectedToInternet) }
        delegate.loadPlaylistSongs(for: playlist, into: template)
        #expect(!texts(template).contains("Song 0"))
        let retry = try #require(delegate.playlistLoadTasks[playlist.id])
        await retry.value
        #expect(delegate.loadStates[playlist.id] == .failed)
        #expect(delegate.openPlaylistSongs[playlist.id]?.isEmpty == true)
        #expect(!texts(template).contains("Play All"))
        #expect(!texts(template).contains("Song 0"))
    }

    @Test("Playback rebuilds preserve initial loading and failure states")
    func persistentStatus() {
        let delegate = CarPlaySceneDelegate()
        let template = CPListTemplate(title: "New", sections: [])
        delegate.latestTemplate = template
        for state in [CarPlayLoadState.loading, .failed, .loaded] {
            delegate.loadStates["latest"] = state
            delegate.rebuildLatestTemplate()
            let before = texts(template)
            delegate.refreshVisibleTemplates()
            #expect(texts(template) == before)
            #expect(template.itemCount == 1)
            #expect(before.first == (state == .loading ? "Loading" : state == .failed ? "Unable to Load" : "No New Songs"))
        }
    }

    @Test("Failed playlist refresh keeps songs and playback actions visible")
    func playlistRefreshFailure() {
        let delegate = CarPlaySceneDelegate()
        let songs = fixtures(30)
        let playlist = Playlist(id: "test", name: "Test", songCount: 30, mosaicMedia: nil, songListDTOs: nil)
        let template = CPListTemplate(title: "Test", sections: [])
        delegate.openPlaylists[playlist.id] = playlist
        delegate.openPlaylistTemplates[playlist.id] = template
        delegate.openPlaylistSongs[playlist.id] = songs
        for state in [CarPlayLoadState.loading, .failed] {
            delegate.loadStates[playlist.id] = state
            delegate.refreshVisibleTemplates()
            #expect(texts(template).contains("Song 0"))
            #expect(texts(template).contains("Play All"))
            let visibleSongs = texts(template).filter { $0.hasPrefix("Song ") }.count
            #expect(template.sections.last?.header == "First \(visibleSongs) of 30 songs")
            #expect(template.itemCount <= CPListTemplate.maximumItemCount)
        }
        #expect(texts(template).first == "Couldn't Refresh")
        #expect(!texts(template).contains("Loading"))
    }

    @Test("Queue handlers use the current queue and reject removed rows")
    func queueSelection() throws {
        let delegate = CarPlaySceneDelegate()
        let songs = fixtures(5)
        var live = songs
        var selected: [String] = []
        delegate.queueSnapshot = { (songs[0].id, live) }
        delegate.selectQueuedSong = { selected.append($0.id) }
        let items = delegate.upNextSections().flatMap(\.items)
        let removedRow = try #require(items[0] as? CPListItem)
        let retainedRow = try #require(items[2] as? CPListItem)
        live.removeAll { $0.id == songs[1].id }
        var completions = 0
        removedRow.handler?(removedRow) { completions += 1 }
        #expect(selected.isEmpty)
        retainedRow.handler?(retainedRow) { completions += 1 }
        #expect(selected == [songs[3].id])
        #expect(live == [songs[0], songs[2], songs[3], songs[4]])
        #expect(completions == 2)
    }

    @Test("The retained pushed queue updates when playback advances")
    func pushedQueueUpdates() {
        let delegate = CarPlaySceneDelegate()
        let songs = fixtures(4)
        var currentID = songs[0].id
        delegate.queueSnapshot = { (currentID, songs) }
        let template = CPListTemplate(title: "Up Next", sections: delegate.upNextSections())
        delegate.queueTemplate = template
        #expect(texts(template) == ["Song 1", "Song 2", "Song 3"])
        currentID = songs[2].id
        delegate.refreshVisibleTemplates()
        #expect(texts(template) == ["Song 3"])
    }

    @Test("Browse paging exposes every item and deduplicates playlist IDs", arguments: [0, 1, 24, 25, 60])
    func libraryPaging(count: Int) {
        let delegate = CarPlaySceneDelegate()
        delegate.serverPlaylists = (0..<count).map { Playlist(id: "p\($0)", name: "Playlist \($0)", songCount: 1, mosaicMedia: nil, songListDTOs: nil) }
        if let first = delegate.serverPlaylists.first { delegate.serverPlaylists.append(first) }
        delegate.loadStates["playlists"] = .loaded
        let template = CPListTemplate(title: "Browse", sections: [])
        delegate.playlistsTemplate = template
        var titles = Set<String>()
        delegate.rebuildPlaylistsTemplate()
        for _ in 0...count {
            titles.formUnion(texts(template).filter { $0.hasPrefix("Playlist ") })
            #expect(template.itemCount <= CPListTemplate.maximumItemCount)
            guard let next = template.sections.flatMap(\.items).compactMap({ $0 as? CPListItem }).first(where: { $0.text == "Next Page" }) else { break }
            next.handler?(next) {}
        }
        #expect(titles.count == count)
    }

    @Test("A cancelled playlist response cannot overwrite a newer result")
    func cancelledResponse() async throws {
        let delegate = CarPlaySceneDelegate()
        var responses: [CheckedContinuation<[Song], any Error>] = []
        delegate.fetchPlaylistSongs = { _ in try await withCheckedThrowingContinuation { responses.append($0) } }
        let playlist = Playlist(id: "test", name: "Test", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        let template = CPListTemplate(title: "Test", sections: [])
        delegate.loadPlaylistSongs(for: playlist, into: template)
        while responses.count < 1 { await Task.yield() }
        let first = try #require(delegate.playlistLoadTasks[playlist.id])
        delegate.loadPlaylistSongs(for: playlist, into: template)
        while responses.count < 2 { await Task.yield() }
        let second = try #require(delegate.playlistLoadTasks[playlist.id])
        responses[1].resume(returning: fixtures(2))
        await second.value
        responses[0].resume(returning: fixtures(1))
        await first.value
        #expect(delegate.openPlaylistSongs[playlist.id]?.count == 2)
        #expect(delegate.loadStates[playlist.id] == .loaded)
    }

    @Test("A failing refresh completes with cached songs and an error")
    func failedRequest() async throws {
        let delegate = CarPlaySceneDelegate()
        delegate.fetchPlaylistSongs = { _ in throw URLError(.notConnectedToInternet) }
        let playlist = Playlist(id: "test", name: "Test", songCount: 2, mosaicMedia: nil, songListDTOs: nil)
        let template = CPListTemplate(title: "Test", sections: [])
        delegate.openPlaylistSongs[playlist.id] = fixtures(2)
        delegate.loadPlaylistSongs(for: playlist, into: template)
        let request = try #require(delegate.playlistLoadTasks[playlist.id])
        await request.value
        #expect(delegate.loadStates[playlist.id] == .failed)
        #expect(texts(template).contains("Song 1"))
        #expect(texts(template).contains("Couldn't Refresh"))
    }

    private func texts(_ template: CPListTemplate) -> [String] {
        template.sections.flatMap(\.items).compactMap { ($0 as? CPListItem)?.text }
    }

    private func fixtures(_ count: Int) -> [Song] {
        (0..<count).map {
            Song(id: String($0), title: "Song \($0)", duration: 180, absolutePath: nil,
                 cloudflareID: nil, coverArt: nil, originalArtists: ["Artist"], coverArtists: nil, userUploaded: false)
        }
    }
}
