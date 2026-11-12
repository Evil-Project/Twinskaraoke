import Foundation
import Testing
@testable import Twinskaraoke

/// The saved copy of Home and New that is shown when a load gets nothing.
@Suite("Home feed store")
struct HomeFeedStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HomeFeedStoreTests-\(UUID().uuidString)", isDirectory: true)

    private var store: HomeFeedStore { HomeFeedStore.disk(directory: directory) }
    private var publicURL: URL { HomeFeedStore.publicFileURL(in: directory) }

    private func song(_ id: String, title: String? = nil) -> Song {
        UITestFixtures.song(id: id, title: title ?? "Song \(id)", artist: "Artist")
    }

    private func songs(_ prefix: String, count: Int) -> [Song] {
        (0 ..< count).map { song("\(prefix)-\($0)") }
    }

    private func placeholder(_ id: String) -> Song {
        song(id, title: "Temporary Stream Audio")
    }

    private func snapshot(savedAt: Date = Date(), apiHost: String = StorageHost.api) -> HomeFeedSnapshot {
        HomeFeedSnapshot(
            savedAt: savedAt,
            apiHost: apiHost,
            trending: songs("trending", count: 3),
            newReleases: songs("release", count: 2),
            topPicks: [UITestFixtures.playlist(id: "pick", name: "Pick", songs: songs("pick", count: 2))],
            topPicksSource: .publicPlaylists,
            latestSetlist: CachedSetlist(KaraokeSetlist(
                playlist: UITestFixtures.playlist(id: "setlist", name: "Setlist", songs: songs("set", count: 2)),
                streamDay: DateComponents(year: 2026, month: 11, day: 1),
                totalDuration: 1260
            ))
        )
    }

    private func suggestionsURLs() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("home-suggestions.") }.map { directory.appendingPathComponent($0) }
    }

    private func rewrite(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    @Test("A saved snapshot reads back with everything the shelves draw")
    func roundTripKeepsWhatShelvesDraw() async throws {
        let saved = snapshot()
        await store.savePublic(saved)
        let loaded = try #require(await store.loadPublic())

        #expect(loaded.trending?.map(\.id) == saved.trending?.map(\.id))
        #expect(loaded.newReleases?.map(\.id) == saved.newReleases?.map(\.id))
        #expect(loaded.topPicks?.map(\.name) == ["Pick"])
        #expect(loaded.topPicks?.first?.songListDTOs?.map(\.id) == ["pick-0", "pick-1"])
        #expect(loaded.topPicksSource == .publicPlaylists)
        let setlist = try #require(loaded.latestSetlist?.setlist)
        #expect(setlist.name == "Setlist")
        #expect(setlist.streamDay == DateComponents(year: 2026, month: 11, day: 1))
        #expect(setlist.totalDuration == 1260)
        #expect(setlist.playlist.songListDTOs?.map(\.id) == ["set-0", "set-1"])

        let account = "user-1"
        await store.saveSuggestions(account, HomeSuggestionsSnapshot(songs: songs("made", count: 2)))
        #expect(await store.loadSuggestions(account)?.songs.map(\.id) == ["made-0", "made-1"])
        #expect(await store.loadSuggestions("user-2") == nil)
    }

    @Test("A save keeps the shelves it doesn't carry")
    func saveMergesIntoTheStoredSnapshot() async throws {
        await store.savePublic(snapshot())
        await store.savePublic(HomeFeedSnapshot(trending: songs("fresh", count: 1)))
        let loaded = try #require(await store.loadPublic())

        #expect(loaded.trending?.map(\.id) == ["fresh-0"])
        #expect(loaded.newReleases?.map(\.id) == ["release-0", "release-1"])
        #expect(loaded.topPicks?.map(\.id) == ["pick"])
        #expect(loaded.latestSetlist?.setlist.id == "setlist")
    }

    @Test("A file from another version is ignored and deleted")
    func versionMismatchIsIgnoredAndDeleted() async throws {
        await store.savePublic(snapshot())
        try rewrite(publicURL) { $0["version"] = 2 }

        #expect(await store.loadPublic() == nil)
        #expect(!FileManager.default.fileExists(atPath: publicURL.path))
    }

    @Test("A file that doesn't decode reads as no cache")
    func corruptFileReadsAsNoCache() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: publicURL)

        #expect(await store.loadPublic() == nil)
        #expect(!FileManager.default.fileExists(atPath: publicURL.path))
    }

    @Test("A snapshot older than 30 days is dropped")
    func snapshotOlderThan30DaysIsDropped() async {
        await store.savePublic(snapshot(savedAt: Date().addingTimeInterval(-31 * 24 * 60 * 60)))

        #expect(await store.loadPublic() == nil)
        #expect(!FileManager.default.fileExists(atPath: publicURL.path))

        await store.savePublic(snapshot(savedAt: Date().addingTimeInterval(-29 * 24 * 60 * 60)))
        #expect(await store.loadPublic() != nil)
    }

    @Test("A shelf carried forward by a later save keeps its own age")
    func carriedForwardShelfKeepsItsOwnAge() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 60 * 60
        await HomeFeedStore.disk(directory: directory, now: { start }).savePublic(snapshot(savedAt: start))
        let later = start.addingTimeInterval(29 * day)
        await HomeFeedStore.disk(directory: directory, now: { later })
            .savePublic(HomeFeedSnapshot(savedAt: later, trending: songs("fresh", count: 1)))

        let reader = HomeFeedStore.disk(directory: directory, now: { start.addingTimeInterval(31 * day) })
        let loaded = try #require(await reader.loadPublic())
        #expect(loaded.trending?.map(\.id) == ["fresh-0"])
        #expect(loaded.newReleases == nil)
        #expect(loaded.topPicks == nil)
        #expect(loaded.topPicksSource == nil)
        #expect(loaded.latestSetlist == nil)
    }

    @Test("A save older than the stored shelf doesn't replace it")
    func olderSaveDoesNotReplaceNewerShelf() async throws {
        let newer = Date()
        let older = newer.addingTimeInterval(-60)
        await store.savePublic(HomeFeedSnapshot(savedAt: newer, trending: songs("newer", count: 1)))
        await store.savePublic(HomeFeedSnapshot(
            savedAt: older,
            trending: songs("older", count: 1),
            newReleases: songs("release", count: 1)
        ))

        let loaded = try #require(await store.loadPublic())
        #expect(loaded.trending?.map(\.id) == ["newer-0"])
        // A shelf the newer save didn't carry still comes from the older one.
        #expect(loaded.newReleases?.map(\.id) == ["release-0"])

        let memory = HomeFeedStore.inMemory()
        await memory.savePublic(HomeFeedSnapshot(savedAt: newer, trending: songs("newer", count: 1)))
        await memory.savePublic(HomeFeedSnapshot(savedAt: older, trending: songs("older", count: 1)))
        #expect(await memory.loadPublic()?.trending?.map(\.id) == ["newer-0"])
    }

    @Test("An account's Made for You isn't replaced by an older save")
    func olderSuggestionsSaveIsIgnored() async throws {
        let newer = Date()
        let older = newer.addingTimeInterval(-60)
        await store.saveSuggestions("a", HomeSuggestionsSnapshot(savedAt: newer, songs: songs("newer", count: 1)))
        await store.saveSuggestions("a", HomeSuggestionsSnapshot(savedAt: older, songs: songs("older", count: 1)))
        #expect(await store.loadSuggestions("a")?.songs.map(\.id) == ["newer-0"])

        let memory = HomeFeedStore.inMemory()
        await memory.saveSuggestions("a", HomeSuggestionsSnapshot(savedAt: newer, songs: songs("newer", count: 1)))
        await memory.saveSuggestions("a", HomeSuggestionsSnapshot(savedAt: older, songs: songs("older", count: 1)))
        #expect(await memory.loadSuggestions("a")?.songs.map(\.id) == ["newer-0"])
    }

    @Test("A snapshot saved for another API host is ignored")
    func otherAPIHostIsIgnored() async {
        await store.savePublic(snapshot(apiHost: "https://api.example.invalid"))

        #expect(await store.loadPublic() == nil)
        #expect(!FileManager.default.fileExists(atPath: publicURL.path))
    }

    @Test("Stream placeholders are left out of every saved list")
    func streamPlaceholdersAreNotSaved() async throws {
        let account = "user-1"
        await store.savePublic(HomeFeedSnapshot(
            trending: [placeholder("p1"), song("real")],
            newReleases: [placeholder("p2")],
            topPicks: [UITestFixtures.playlist(id: "pick", name: "Pick", songs: [placeholder("p3"), song("kept")])],
            topPicksSource: .setlists,
            latestSetlist: CachedSetlist(KaraokeSetlist(
                playlist: UITestFixtures.playlist(id: "setlist", name: "Setlist", songs: [placeholder("p4")]),
                streamDay: nil,
                totalDuration: nil
            ))
        ))
        await store.saveSuggestions(account, HomeSuggestionsSnapshot(songs: [placeholder("p5"), song("made")]))

        let loaded = try #require(await store.loadPublic())
        #expect(loaded.trending?.map(\.id) == ["real"])
        // Nothing left after filtering: stored as absent, not as an empty shelf.
        #expect(loaded.newReleases == nil)
        #expect(loaded.topPicks?.first?.songListDTOs?.map(\.id) == ["kept"])
        #expect(loaded.latestSetlist == nil)
        #expect(await store.loadSuggestions(account)?.songs.map(\.id) == ["made"])

        let text = try String(contentsOf: publicURL, encoding: .utf8)
        #expect(!text.contains("Temporary Stream Audio"))
    }

    @Test("A snapshot with nothing in it is not written")
    func emptySnapshotIsNotWritten() async {
        await store.savePublic(HomeFeedSnapshot(trending: [], newReleases: [placeholder("p")]))
        await store.saveSuggestions("user-1", HomeSuggestionsSnapshot(songs: [placeholder("p")]))

        #expect(!FileManager.default.fileExists(atPath: publicURL.path))
        #expect(suggestionsURLs().isEmpty)
    }

    @Test("An oversized snapshot drops the playlists' songs, and is skipped if still too big")
    func oversizedSnapshotDropsPlaylistSongsThenSkips() async throws {
        let bigPicks = (0 ..< 12).map { index in
            UITestFixtures.playlist(id: "pick-\(index)", name: "Pick \(index)", songs: songs("pick-\(index)", count: 900))
        }
        await store.savePublic(HomeFeedSnapshot(
            trending: songs("trending", count: 3),
            topPicks: bigPicks,
            topPicksSource: .setlists
        ))
        let loaded = try #require(await store.loadPublic())
        #expect(loaded.trending?.count == 3)
        #expect(loaded.topPicks?.count == 12)
        #expect(loaded.topPicks?.allSatisfy { $0.songListDTOs == nil } == true)
        #expect(loaded.topPicks?.first?.songCount == 900)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: publicURL.path)[.size] as? Int)
        #expect(size <= HomeFeedStore.maximumFileSize)

        // Too big even without playlist songs: the write is skipped and the
        // snapshot already on disk is left alone.
        await store.savePublic(HomeFeedSnapshot(trending: songs("huge", count: 12000)))
        #expect(try #require(await store.loadPublic()).trending?.count == 3)
    }

    @Test("Only the four most recently used accounts keep their Made for You")
    func suggestionFilesArePrunedToFour() async throws {
        let now = Date()
        for (index, account) in ["a", "b", "c", "d", "e"].enumerated() {
            await store.saveSuggestions(account, HomeSuggestionsSnapshot(songs: songs(account, count: 1)))
            let url = HomeFeedStore.suggestionsFileURL(in: directory, account: account)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(Double(index - 10) * 60)],
                ofItemAtPath: url.path
            )
        }
        await store.saveSuggestions("f", HomeSuggestionsSnapshot(songs: songs("f", count: 1)))

        #expect(suggestionsURLs().count == 4)
        for account in ["c", "d", "e", "f"] {
            #expect(await store.loadSuggestions(account) != nil)
        }
        for account in ["a", "b"] {
            #expect(await store.loadSuggestions(account) == nil)
        }
    }

    @Test("An account's file name doesn't contain its user ID")
    func accountFileNameDoesNotContainUserID() async throws {
        let account = "8b1f0c2e-user-42"
        await store.saveSuggestions(account, HomeSuggestionsSnapshot(songs: songs("made", count: 1)))

        let url = try #require(suggestionsURLs().first)
        #expect(!url.lastPathComponent.contains(account))
        #expect(url == HomeFeedStore.suggestionsFileURL(in: directory, account: account))
        #expect(url.lastPathComponent.hasPrefix("home-suggestions.v1."))
    }

    @Test("Saved files hold no token, header or account name")
    func fileContainsNoAuthorizationOrToken() async throws {
        let account = "user-secret-id"
        await store.savePublic(snapshot())
        await store.saveSuggestions(account, HomeSuggestionsSnapshot(songs: songs("made", count: 2)))

        for url in [publicURL] + suggestionsURLs() {
            let text = try String(contentsOf: url, encoding: .utf8).lowercased()
            for forbidden in ["authorization", "bearer", "token", "guest", account] {
                #expect(!text.contains(forbidden), "\(url.lastPathComponent) contains \(forbidden)")
            }
        }
    }

    @Test("The in-memory and disabled stores behave as their names say")
    func inMemoryAndDisabledStores() async {
        let memory = HomeFeedStore.inMemory()
        await memory.savePublic(snapshot())
        await memory.saveSuggestions("a", HomeSuggestionsSnapshot(songs: songs("made", count: 1)))
        #expect(await memory.loadPublic()?.trending?.count == 3)
        #expect(await memory.loadSuggestions("a")?.songs.count == 1)
        #expect(await memory.loadSuggestions("b") == nil)

        let disabled = HomeFeedStore.disabled
        await disabled.savePublic(snapshot())
        #expect(await disabled.loadPublic() == nil)
    }
}
