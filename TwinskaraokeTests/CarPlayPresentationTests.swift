import CarPlay
import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("CarPlay presentation", .serialized)
struct CarPlayPresentationTests {
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
        delegate.category = .browse
        let template = CPListTemplate(title: "Browse", sections: [])
        delegate.categoryTemplate = template
        var titles = Set<String>()
        delegate.rebuildCategoryTemplate()
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
