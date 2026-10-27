import Foundation
import Security
import Testing
@testable import Twinskaraoke

@Suite("Launch restoration")
struct LaunchRestorationTests {
    @Test func keychainUnavailableIsNotMissing() {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed] {
            #expect(CredentialStore.classifyRead(status: status, data: nil) == .unavailable(status))
        }
        #expect(CredentialStore.classifyRead(status: errSecItemNotFound, data: nil) == .missing)
        #expect(CredentialStore.classifyRead(status: errSecSuccess, data: Data("secret".utf8)) == .available("secret"))
        #expect(CredentialStore.classifyRead(status: errSecSuccess, data: Data()) == .unavailable(errSecDecode))
    }

    @Test func unavailableCredentialDoesNotCreateAnonymousRequest() {
        #expect(throws: CredentialStore.StoreError.self) {
            try KaraokeAPIClient.request(path: "/api/playlists", readToken: {
                throw CredentialStore.StoreError.keychain(errSecInteractionNotAllowed)
            })
        }
    }

    @Test func malformedPlaylistPayloadIsNotAnEmptyLibrary() throws {
        #expect(throws: (any Error).self) {
            try KaraokeAPIClient.decodePlaylists(from: Data("{\"error\":\"unavailable\"}".utf8))
        }
        #expect(throws: (any Error).self) {
            try KaraokeAPIClient.decodePlaylists(from: Data("[{\"unexpected\":true}]".utf8))
        }
        #expect(try KaraokeAPIClient.decodePlaylists(from: Data("[]".utf8)).isEmpty)
    }

    @MainActor @Test func failedPublicPlaylistLoadCanRetry() async {
        let loader = FailingPageLoader()
        let model = PublicPlaylistsViewModel { _, _ in try await loader.load() }
        model.loadIfNeeded()
        while model.isLoadingMore { await Task.yield() }
        #expect(model.errorMessage != nil)
        model.loadIfNeeded()
        while model.isLoadingMore { await Task.yield() }
        #expect(model.errorMessage == nil)
        #expect(await loader.calls == 2)
        model.loadIfNeeded()
        #expect(await loader.calls == 2)
    }

    @MainActor @Test func startupDoesNotProbeOrDeleteAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = UITestFixtures.song(id: "restored", title: "Saved", artist: "Artist")
        let directory = root.appendingPathComponent(song.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(song).write(to: directory.appendingPathComponent("metadata.json"))
        let audio = directory.appendingPathComponent("main.mp3")
        let bytes = Data("a temporarily undecodable file".utf8)
        try bytes.write(to: audio)
        let result = DownloadManager.scanExistingDownloads(in: root)
        #expect(result.validIDs == [song.id])
        #expect(!result.hadFailures)
        #expect(try Data(contentsOf: audio) == bytes)
        try Data("invalid metadata".utf8).write(to: directory.appendingPathComponent("metadata.json"))
        #expect(DownloadManager.scanExistingDownloads(in: root).hadFailures)
        #expect(try Data(contentsOf: audio) == bytes)
    }

    @MainActor @Test func startupIgnoresSidecarsStagingAndDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let song = UITestFixtures.song(id: "sidecars", title: "Saved", artist: "Artist")
        let directory = root.appendingPathComponent(song.id)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(song).write(to: directory.appendingPathComponent("metadata.json"))
        for name in ["main.source", "main.source.backup", "main.mp3.nkz", "main.partial.mp3", "main.promoting-test.mp3"] {
            try Data("sidecar".utf8).write(to: directory.appendingPathComponent(name))
        }
        try fm.createDirectory(at: directory.appendingPathComponent("main.mp3"), withIntermediateDirectories: true)
        let result = DownloadManager.scanExistingDownloads(in: root)
        #expect(result.validIDs.isEmpty)
        #expect(!result.hadFailures)
        #expect(try fm.contentsOfDirectory(atPath: directory.path).count == 7)
        // Discovery checks file identity, never decoder availability.
        try Data("temporarily undecodable".utf8).write(to: directory.appendingPathComponent("main.m4a"))
        #expect(DownloadManager.scanExistingDownloads(in: root).validIDs == [song.id])
    }

    @Test func reconciliationPreservesLiveChangesAndUnavailableFiles() {
        #expect(DownloadManager.restorationMissingIDs(
            starting: ["gone", "completed", "active", "saved"], discovered: ["saved"],
            changed: ["completed"], inProgress: ["active"], hadFailures: false) == ["gone"])
        #expect(DownloadManager.restorationMissingIDs(
            starting: ["unreadable"], discovered: [], changed: [], inProgress: [], hadFailures: true).isEmpty)
    }

    @MainActor @Test func playbackPreservesDownloadWhenOnlySignatureChanges() throws {
        let manager = DownloadManager.shared
        let song = Song(id: "signature-test-\(UUID().uuidString)", title: "Saved", duration: 0,
            absolutePath: "https://example.com/song.mp3?token=new", cloudflareID: nil,
            coverArt: nil, originalArtists: nil, coverArtists: nil, userUploaded: false)
        let audio = manager.localURL(for: song.id)
        let directory = audio.deletingLastPathComponent()
        let source = directory.appendingPathComponent("main.source")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let bytes = Data("temporarily unreadable audio".utf8)
        try bytes.write(to: audio)
        let originalSource = Data("https://example.com/song.mp3?token=old".utf8)
        try originalSource.write(to: source)
        // A failed decoder probe still must not erase the signed-URL download.
        #expect(manager.playableURL(for: song) == nil)
        #expect(try Data(contentsOf: audio) == bytes)
        #expect(try Data(contentsOf: source) == originalSource)
    }

    @Test func signedURLRotationPreservesContentIdentity() {
        #expect(DownloadManager.sameAudioResource("https://example.com/song?token=old", "https://example.com/song?token=new"))
        #expect(!DownloadManager.sameAudioResource("https://example.com/song?version=1", "https://example.com/song?version=2"))
    }
}

private actor FailingPageLoader {
    var calls = 0
    func load() throws -> [Playlist] {
        calls += 1
        if calls == 1 { throw URLError(.notConnectedToInternet) }
        return []
    }
}

@Suite("iOS 27 API audit")
struct IOS27APIAuditTests {
    @Test func unavailableAccountDoesNotSelectGuestHistory() {
        #expect(VideoResumeStore.accountIdentity(for: nil) == nil)
        #expect(VideoResumeStore.accountIdentity(for: .signedOut) == "guest")
        let signedIn = WatchSessionLink.Descriptor(isSignedIn: true, userID: "user", generation: 1)
        #expect(VideoResumeStore.accountIdentity(for: signedIn) == "user")
    }

    @Test func unavailablePhoneCredentialIsNotASignOut() {
        let reply = WatchSessionLink.tokenReply(for: .unavailable(errSecInteractionNotAllowed))
        #expect(WatchSessionLink.decodeTokenReply(reply) == .unavailable)
        #expect(WatchSessionLink.decodeTokenReply([:]) == .unavailable)
        #expect(WatchSessionLink.decodeTokenReply(WatchSessionLink.tokenReply(for: .missing)) == .signedOut)
        #expect(WatchSessionLink.decodeTokenReply(WatchSessionLink.tokenReply(for: .available("token"))) == .available("token"))
    }

    @MainActor @Test func unavailablePaginationCredentialDoesNotSendAnonymousRequest() async {
        var didFetch = false
        let loader = PlaylistListLoader(readToken: {
            throw CredentialStore.StoreError.keychain(errSecInteractionNotAllowed)
        }, fetchData: { _ in
            didFetch = true
            return Data("[]".utf8)
        })
        let playlist = Playlist(id: "saved", name: "Saved", songCount: 0, mosaicMedia: nil, songListDTOs: nil)
        loader.bootstrap(initial: [playlist]) { _, _ in "https://example.com/playlists" }
        loader.loadMoreIfNeeded(current: playlist)
        while loader.isLoadingMore { await Task.yield() }
        #expect(!didFetch)
        #expect(loader.playlists == [playlist])
    }
}
