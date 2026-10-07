import Foundation
import Testing
import UIKit
@testable import Twinskaraoke

@Suite("iOS system integration")
struct SystemIntegrationTests {
    @Test func routesRoundTrip() {
        let routes: [AppRoute] = [.home, .radio, .search, .library, .nowPlaying, .lyrics, .song("a b?&#שלום"), .playlist("abc-123")]
        for route in routes { #expect(AppRoute(url: route.url) == route) }
    }
    @Test func rejectsMalformedRoutes() {
        for value in ["https://search", "twinskaraoke://unknown", "twinskaraoke://song", "twinskaraoke://song/", "twinskaraoke://song/a/b", "twinskaraoke://song/%2F", "twinskaraoke://playlist/..", "twinskaraoke://search?token=secret", "twinskaraoke://user@library", "twinskaraoke://home:90", "twinskaraoke://search/extra"] {
            #expect(URL(string: value).flatMap(AppRoute.init(url:)) == nil)
        }
    }
    @Test func snapshotRoundTripAndFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = WidgetSnapshotStore(directory: directory)
        let reader = WidgetSnapshotStore(directory: directory)
        #expect(reader.readPlayback().song == nil)
        var snapshot = PlaybackWidgetSnapshot(song: WidgetSong(id: "song", title: "Title", artist: "Artist"), isPlaying: true)
        try writer.write(snapshot)
        #expect(reader.readPlayback() == snapshot)
        snapshot.schemaVersion = 99
        try writer.write(snapshot)
        #expect(reader.readPlayback().song == nil)
        try Data("{broken".utf8).write(to: directory.appendingPathComponent("playback.json"))
        #expect(reader.readPlayback().song == nil)
        var library = LibraryWidgetSnapshot()
        library.recent = [WidgetPlaylist(id: "recent", name: "Recent")]
        try writer.write(library)
        #expect(reader.readLibrary() == library)
        library.schemaVersion = 0
        try writer.write(library)
        #expect(reader.readLibrary().recent.isEmpty)
    }
    @Test func suggestionsAreOrderedAndDeduplicated() {
        var library = LibraryWidgetSnapshot()
        library.accountAvailable = true
        library.pinned = [WidgetPlaylist(id: "one", name: "One")]
        library.recent = [WidgetPlaylist(id: "one", name: "One"), WidgetPlaylist(id: "two", name: "Two")]
        #expect(library.suggestions.map(\.id) == ["__favorites__", "one", "two"])
        library.accountAvailable = false
        #expect(!library.suggestions.contains { $0.id == "__favorites__" })
    }
    @Test func unavailableGroupWriteThrows() {
        #expect(throws: CocoaError.self) { try WidgetSnapshotStore(directory: nil).write(PlaybackWidgetSnapshot()) }
    }
    @MainActor @Test func artworkIsBoundedAndRejectsTraversal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetArtworkStore(directory: directory)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400)).jpegData(withCompressionQuality: 1) { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        }
        for index in 0..<5 { _ = try store.store(data, key: "\(index)", limit: 2) }
        let files = try FileManager.default.contentsOfDirectory(at: store.directory!, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        let image = UIImage(contentsOfFile: files[0].path)!
        #expect(max(image.size.width, image.size.height) <= 400)
        #expect(image.size.width == image.size.height)
        let resized = URL(string: "https://images.neurokaraoke.com/cdn-cgi/image/width=240,quality=80/example/public")!
        #expect(WidgetArtworkStore.originalURL(for: resized)?.absoluteString == "https://images.neurokaraoke.com/example/public")
        let legacy = URL(string: "https://images.neurokaraoke.com/example/public/width=240,quality=80")!
        #expect(WidgetArtworkStore.originalURL(for: legacy)?.absoluteString == "https://images.neurokaraoke.com/example/public")
        #expect(store.url(for: "../private.jpg") == nil)
        #expect(WidgetArtworkStore.filename(for: "a") == WidgetArtworkStore.filename(for: "a"))
        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.directory!.path))
    }
    @MainActor @Test func routerSelectsDestination() {
        let router = AppRouter(isSplashBlocking: { false })
        router.open(.search)
        #expect(router.section == .search)
        router.open(.playlist("one"))
        #expect(router.section == .library)
        #expect(router.detail == .playlist("one"))
        router.open(.radio)
        #expect(router.detail == nil)
        #expect(router.section == .radio)
    }
    @Test func errorMessagesAndTimerOptionsExist() {
        #expect(SleepTimerDuration.thirty.minutes == 30)
        #expect(SleepTimerDuration.hour.minutes == 60)
        #expect(!String(localized: SystemIntentError.signIn.localizedStringResource).isEmpty)
        #expect(!String(localized: SystemIntentError.noNext.localizedStringResource).isEmpty)
    }
    @Test func playlistCollageSurvivesSnapshotRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        var library = LibraryWidgetSnapshot()
        library.pinned = [WidgetPlaylist(id: "pinned", name: "Pinned", artworkFilename: "a.jpg", artworkFilenames: ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])]
        try store.write(library)
        #expect(store.readLibrary().pinned.first?.artworkFilenames == ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
    }
    @Test func publicRadioFallbackAndMetadata() {
        let missing = WidgetRadioSnapshot.decode(Data("{}".utf8))
        #expect(missing.snapshot.title == "Twinskaraoke Radio")
        #expect(missing.artworkURL == nil)
        let payload = Data(#"{"now_playing":{"song":{"title":"Live track","artist":"Artist","art":"https://example.com/art.jpg"}}}"#.utf8)
        let result = WidgetRadioSnapshot.decode(payload)
        #expect(result.snapshot.title == "Live track")
        #expect(result.snapshot.artist == "Artist")
        #expect(result.artworkURL?.scheme == "https")
        #expect(WidgetRadioRepository.refreshInterval == 900)
    }
    @Test func atomicWritesNeverExposePartialJSON() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = PlaybackWidgetSnapshot(song: WidgetSong(id: "one", title: "One", artist: "Artist"))
        try store.write(snapshot)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try store.write(snapshot)
                    #expect(store.readPlayback().song?.id == "one")
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func hostAndExtensionRegisterMatchingIntentsAndGroup() throws {
        let host = Bundle.main
        let hostGroup = try #require(host.object(forInfoDictionaryKey: "WidgetAppGroupIdentifier") as? String)
        #expect(hostGroup == WidgetSnapshotStore.groupID)
        let extensions = try #require(host.builtInPlugInsURL)
        let widget = try #require(Bundle(url: extensions.appendingPathComponent("TwinskaraokeWidgets.appex")))
        #expect(widget.object(forInfoDictionaryKey: "WidgetAppGroupIdentifier") as? String == hostGroup)
        let names = ["IOSTogglePlaybackIntent", "IOSNextTrackIntent", "IOSPreviousTrackIntent", "IOSPlayPlaylistIntent", "IOSPlayFavoritesIntent", "IOSPlayDownloadsIntent", "IOSToggleRepeatIntent", "IOSToggleShuffleIntent"]
        for bundle in [host, widget] {
            let metadata = bundle.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
            let data = try Data(contentsOf: metadata)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let actions = try #require(object["actions"] as? [String: Any])
            for name in names { #expect(actions[name] != nil) }
            for name in ["IOSStartSleepTimerIntent", "IOSFavoriteCurrentSongIntent", "IOSOpenSearchIntent", "IOSShowCurrentSongIntent"] {
                #expect((actions[name] != nil) == (bundle == host))
            }
        }
        // CI intentionally builds without signing, so its host cannot obtain
        // an entitled container. Signed simulator/device runs verify access.
        if FileManager.default.fileExists(atPath: host.bundleURL.appendingPathComponent("_CodeSignature").path) {
            #expect(WidgetSnapshotStore().directory != nil)
        }
    }
    @Test func playbackProgressAnchorsAndClamps() {
        let date = Date(timeIntervalSince1970: 1_000)
        var snapshot = PlaybackWidgetSnapshot(updatedAt: date, isPlaying: true)
        snapshot.elapsedSeconds = 30
        snapshot.durationSeconds = 100
        #expect(snapshot.elapsed(at: date.addingTimeInterval(20)) == 50)
        #expect(snapshot.elapsed(at: date.addingTimeInterval(200)) == 100)
        #expect(snapshot.playbackInterval?.lowerBound == date.addingTimeInterval(-30))
        snapshot.isPlaying = false
        #expect(snapshot.elapsed(at: date.addingTimeInterval(20)) == 30)
        #expect(snapshot.playbackInterval == nil)
    }
    @MainActor @Test func playlistTilesRouteToTheirCollections() {
        #expect(PlaylistEntity(WidgetPlaylist(id: "abc", name: "Actual Playlist")).route == .playlist("abc"))
        #expect(PlaylistEntity(WidgetPlaylist(id: "__favorites__", name: "Favorites")).route == .playlist("__favorites__"))
        #expect(PlaylistEntity(WidgetPlaylist(id: "__downloads__", name: "Downloads")).route == .playlist("__downloads__"))
        #expect(PlaylistEntity(WidgetPlaylist(id: "__radio__", name: "Radio")).route == .radio)
    }

}
