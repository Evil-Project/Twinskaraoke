import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import WatchConnectivity
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Watch playback regressions")
struct WatchPlaybackRegressionTests {
    @MainActor
    @Test("The latest song or radio request owns one in-flight activation")
    func activationCoalescesPlaybackRequests() {
        let activation = WatchActivationProbe()
        let session = activation.makeSession()
        var settled: [String] = []
        session.request { _ in settled.append("song") }
        session.request { _ in settled.append("next song") }
        session.request { _ in settled.append("radio") }
        #expect(activation.completions.count == 1)
        activation.completions.first?(.success(()))
        #expect(settled == ["radio"])
        #expect(session.isActive)
        session.request { _ in settled.append("resume") }
        #expect(settled == ["radio", "resume"])
        #expect(activation.completions.count == 1)
    }

    @MainActor
    @Test("Pause or replacement drops the old request and a failed activation can retry")
    func activationCancellationAndRetry() throws {
        let activation = WatchActivationProbe()
        let session = activation.makeSession()
        var failure: NSError?
        session.request { _ in Issue.record("The paused player received an activation result") }
        session.cancelPendingPlayback()
        let error = NSError(domain: "Activation test", code: 42)
        let cancelled = try #require(activation.completions.first)
        cancelled(.failure(error))
        #expect(!session.isActive)

        session.request { result in
            if case let .failure(error) = result { failure = error as NSError }
        }
        let failed = try #require(activation.completions.dropFirst().first)
        failed(.failure(error))
        #expect(failure == error)
        session.request { _ in }
        let retried = try #require(activation.completions.dropFirst(2).first)
        retried(.success(()))
        #expect(session.isActive)
    }

    @MainActor
    @Test("Invalidation discards stale success and failure before activating for a new request")
    func activationInvalidation() throws {
        for staleResult: Result<Void, Error> in [.success(()), .failure(CancellationError())] {
            let activation = WatchActivationProbe()
            let session = activation.makeSession()
            session.request { _ in Issue.record("An invalidated player received an activation result") }
            session.invalidate()
            var settled = false
            session.request { _ in settled = true }
            #expect(activation.completions.count == 1)
            let stale = try #require(activation.completions.first)
            stale(staleResult)
            #expect(!session.isActive)
            #expect(!settled)
            #expect(activation.completions.count == 2)
            let current = try #require(activation.completions.dropFirst().first)
            current(.success(()))
            #expect(session.isActive)
            #expect(settled)
        }
    }

    @MainActor
    @Test("A late activation after relinquishing output is deactivated before a new request")
    func relinquishedActivation() throws {
        let activation = WatchActivationProbe()
        var deactivation: (@MainActor () -> Void)?
        let session = WatchAudioSessionCoordinator(
            activate: { activation.completions.append($0) },
            deactivate: { deactivation = $0 }
        )
        session.request { _ in Issue.record("The relinquished player received an activation result") }
        session.relinquish()
        var resumed = false
        session.request { _ in resumed = true }

        let stale = try #require(activation.completions.first)
        stale(.success(()))
        #expect(activation.completions.count == 1)
        #expect(!session.isActive)
        #expect(!resumed)

        let released = try #require(deactivation)
        released()
        #expect(activation.completions.count == 2)
        let current = try #require(activation.completions.dropFirst().first)
        current(.success(()))
        #expect(session.isActive)
        #expect(resumed)
    }

    @MainActor
    @Test("Relinquishing an already-active session releases it once")
    func relinquishActiveSession() throws {
        let activation = WatchActivationProbe()
        var deactivations: [@MainActor () -> Void] = []
        let session = WatchAudioSessionCoordinator(
            activate: { activation.completions.append($0) },
            deactivate: { deactivations.append($0) }
        )
        session.request { _ in }
        let active = try #require(activation.completions.first)
        active(.success(()))
        session.relinquish()
        session.relinquish()
        #expect(!session.isActive)
        #expect(deactivations.count == 1)
    }

    @MainActor
    @Test("Watch radio starts only after activation and pause drops pending playback")
    func managerRadioWaitsForActivation() async throws {
        let fixture = try WatchRadioActivationFixture()
        defer { fixture.cleanUp() }

        try await fixture.tuneIn(activationCount: 1)
        #expect(fixture.starts == 0)
        #expect(fixture.manager.togglePlayPause())
        let first = try #require(fixture.activation.completions.first)
        first(.failure(URLError(.cancelled)))
        #expect(fixture.starts == 0)
        #expect(fixture.manager.playbackError == nil)

        #expect(fixture.manager.togglePlayPause())
        let second = try #require(fixture.activation.completions.dropFirst().first)
        second(.success(()))
        #expect(fixture.starts == 1)
    }

    @MainActor
    @Test("An interruption or media reset drops radio activation and permits a fresh request", arguments: [false, true])
    func managerInvalidatesRadioActivation(reset: Bool) async throws {
        let fixture = try WatchRadioActivationFixture()
        defer { fixture.cleanUp() }

        try await fixture.tuneIn(activationCount: 1)
        if reset { fixture.manager.handleMediaServicesReset() }
        else { fixture.manager.audioSessionInterruptionBegan() }
        let stale = try #require(fixture.activation.completions.first)
        stale(.success(()))
        #expect(fixture.starts == 0)
        #expect(!fixture.manager.isPlaying)
        #expect(!fixture.manager.isLoading)

        #expect(fixture.manager.togglePlayPause())
        try await fixture.waitForActivation(count: 2)
        let current = try #require(fixture.activation.completions.dropFirst().first)
        current(.success(()))
        #expect(fixture.starts == 1)
    }

    @MainActor
    @Test("A phone snapshot replaces pending Watch radio and releases late activation")
    func managerRelinquishesRadioForSnapshot() async throws {
        let fixture = try WatchRadioActivationFixture()
        defer { fixture.cleanUp() }

        try await fixture.tuneIn(activationCount: 1)
        let song = UITestFixtures.song(id: "phone-song", title: "Phone Song", artist: "Artist")
        fixture.manager.applyCompanionSnapshot(CompanionPlayback.Snapshot(
            sessionID: UUID(), revision: 1, owner: .phone, song: song, queue: [song],
            isPlaying: false, isRadio: false, radioArtworkURL: nil, position: 12,
            duration: 180, isShuffled: false, repeatSetting: .off, error: nil, updatedAt: .now
        ))
        let stale = try #require(fixture.activation.completions.first)
        stale(.success(()))
        #expect(fixture.starts == 0)
        #expect(fixture.deactivations == 1)
        #expect(fixture.manager.currentSong?.id == song.id)
        #expect(!fixture.manager.isRadioMode)
        #expect(!fixture.manager.isLoading)
    }

    @MainActor
    @Test("Stale-account cancellation never falls back to a direct playlist fetch")
    func playlistCancellation() async {
        do {
            _ = try await UserPlaylistsViewModel.loadWithFallback(companion: { throw CancellationError() }, direct: {
                Issue.record("A stale account started an independent playlist request")
                return []
            })
            Issue.record("Expected cancellation to propagate")
        } catch is CancellationError {
            // The canceled account request must remain canceled.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test("Companion network failures retain the independent playlist fallback")
    func playlistNetworkFallback() async throws {
        let expected = Playlist(id: "mine", name: "Mine", songCount: 0, mosaicMedia: nil, songListDTOs: nil)
        let loaded = try await UserPlaylistsViewModel.loadWithFallback(companion: { throw URLError(.notConnectedToInternet) }, direct: { [expected] })
        #expect(loaded.map(\.id) == [expected.id])
    }

    @MainActor
    @Test("MediaPlayer can request cached artwork on a background thread")
    func backgroundArtworkRequest() async throws {
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0fQAAAAASUVORK5CYII="))
        let image = try #require(UIImage(data: imageData))
        let artwork = AudioManager.makeNowPlayingArtwork(image)
        let request = BackgroundArtworkRequest(artwork: artwork)
        let size = await Task.detached { request.imageSize() }.value
        #expect(size == CGSize(width: 1, height: 1))
    }

    @Test("Personal playlists decode without optional server presentation flags")
    func missingPlaylistFields() throws {
        let data = Data(#"[{"id":"mine","name":"My Mix","songListDTOs":[{"id":"one","title":"Song"}]}]"#.utf8)
        let playlists = try JSONDecoder().decode([UserPlaylist].self, from: data)
        #expect(playlists.first?.asPlaylist().songCount == 1)
        #expect(playlists.first?.asPlaylist().isPersonal == true)
    }

    @Test("Touch seeking maps linearly and clamps invalid or out-of-range gestures")
    func touchSeeking() {
        #expect(WatchPlaybackPosition.time(at: 25, width: 100, duration: 240) == 60)
        #expect(WatchPlaybackPosition.time(at: -20, width: 100, duration: 240) == 0)
        #expect(WatchPlaybackPosition.time(at: 120, width: 100, duration: 240) == 240)
        #expect(WatchPlaybackPosition.time(at: .nan, width: 100, duration: 240) == 0)
        #expect(WatchPlaybackPosition.time(at: 50, width: 0, duration: 240) == 0)
    }

    @MainActor
    @Test("A personal playlist without inline covers obtains artwork from its details")
    func personalCoverFallback() async {
        var partial = Playlist(id: "mine", name: "Mix", songCount: 1, mosaicMedia: nil, songListDTOs: nil)
        partial.isPersonal = true
        let full = Playlist(id: "mine", name: "Mix", songCount: 1,
                            mosaicMedia: [Media(absolutePath: "https://example.com/already-resized.jpg")], songListDTOs: nil)
        let loader = WatchPlaylistCoverLoader(loadDetail: { _ in full })
        await loader.load(partial)
        #expect(loader.urls.first?.absoluteString == "https://example.com/already-resized.jpg")
    }

    @Test("Download errors distinguish denied access from missing audio")
    func downloadResponseErrors() {
        let url = URL(string: "https://example.com/audio")!
        #expect(WatchDownloads.responseError(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))?.contains("sync your account") == true)
        #expect(WatchDownloads.responseError(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))?.contains("unavailable") == true)
    }

    @Test("A full thousand-song playlist survives a bounded companion message")
    func largePlaylistMessage() throws {
        let queue = (0..<1000).map { UITestFixtures.song(id: "song-\($0)", title: "A personal playlist song \($0)", artist: "Artist") }
        let command = CompanionPlayback.Command(action: .play, song: queue[0], queue: queue, shuffleEnabled: true)
        let data = try #require(CompanionPlayback.encode(command))
        #expect(data.count < 60_000)
        #expect(CompanionPlayback.encode(command) == data)
        let decoded = try #require(CompanionPlayback.decode(CompanionPlayback.Command.self, from: data))
        #expect(decoded.queue?.count == 1000)
        #expect(decoded.shuffleEnabled == true)
        #expect(decoded.queue == queue)
    }

    @Test("Saved JSON from a previous build remains readable")
    func legacyJSON() throws {
        let command = CompanionPlayback.Command(action: .pause)
        let data = try JSONEncoder().encode(command)
        #expect(CompanionPlayback.decode(CompanionPlayback.Command.self, from: data)?.id == command.id)
        #expect(CompanionPlayback.decode(CompanionPlayback.Command.self, from: Data("NKP1broken".utf8)) == nil)
    }

    @Test("Oversized playlists do not report a disconnected phone")
    func payloadError() {
        let error = NSError(domain: WCErrorDomain, code: WCError.Code.payloadTooLarge.rawValue)
        #expect(WatchAuthManager.playbackMessageError(error).contains("playlist is too large"))
    }

    @MainActor
    @Test("Companion sleep deadlines mirror without triggering a second expiry")
    func sleepMirror() {
        var expired = false
        let timer = SleepTimer { expired = true }
        timer.mirror(deadline: Date().addingTimeInterval(60), endsWithCurrentSong: false)
        #expect(timer.isActive)
        timer.checkExpiry(now: Date().addingTimeInterval(120))
        #expect(!expired)
        #expect(timer.isActive)
        timer.cancel()
        #expect(!timer.isActive)
        #expect(!expired)
        timer.startEndOfSong()
        #expect(timer.consumeEndOfSong())
        #expect(!timer.consumeEndOfSong())
    }
}

@MainActor
private final class WatchActivationProbe {
    var completions: [WatchAudioSessionCoordinator.Completion] = []

    func makeSession() -> WatchAudioSessionCoordinator {
        WatchAudioSessionCoordinator(activate: { self.completions.append($0) })
    }
}

@MainActor
private final class WatchRadioActivationFixture {
    let activation = WatchActivationProbe()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    var starts = 0
    var deactivations = 0
    lazy var manager = AudioManager(
        audioSession: WatchAudioSessionCoordinator(
            activate: { [weak self] completion in self?.activation.completions.append(completion) },
            deactivate: { [weak self] completion in
                self?.deactivations += 1
                completion()
            }
        ),
        canPlayLocally: { true },
        startPlayer: { [weak self] _ in self?.starts += 1 }
    )

    init() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = 8000
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    func tuneIn(activationCount: Int) async throws {
        let song = UITestFixtures.song(id: "local-radio", title: "Radio", artist: "Artist")
        manager.playRadio(streamURL: url, song: song, artworkURL: nil)
        try await waitForActivation(count: activationCount)
    }

    func waitForActivation(count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while activation.completions.count < count, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        try #require(activation.completions.count == count)
    }

    func cleanUp() {
        manager.stopForOutputTransfer()
        try? FileManager.default.removeItem(at: url)
    }
}

// MediaPlayer invokes the escaping request handler from outside Swift's actor
// model. This wrapper deliberately reproduces that framework boundary.
nonisolated private struct BackgroundArtworkRequest: @unchecked Sendable {
    let artwork: MPMediaItemArtwork
    func imageSize() -> CGSize? { artwork.image(at: CGSize(width: 1, height: 1))?.size }
}
