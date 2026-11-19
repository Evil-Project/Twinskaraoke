import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Transition coordinator")
struct TransitionCoordinatorTests {
    @Test(
        "Crossfade and Auto Mix skip transitions involving tracks under 45 seconds",
        arguments: [false, true]
    )
    @MainActor
    func shortTracksDoNotPrepareMixes(autoMixEnabled: Bool) throws {
        for (outgoingDuration, incomingDuration, shouldPrepare) in [(44.9, 60, false), (60, 44, false), (45, 45, true)] {
            let coordinator = TransitionCoordinator()
            defer { coordinator.reset() }
            let outgoing = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"outgoing","title":"Outgoing","duration":60}"#.utf8))
            let incoming = try JSONDecoder().decode(
                Song.self, from: Data(#"{"id":"incoming","title":"Incoming","duration":\#(incomingDuration)}"#.utf8)
            )
            coordinator.poll(
                currentTime: outgoingDuration - 5, totalDuration: outgoingDuration, currentSong: outgoing,
                target: PlaybackQueueState.Entry(song: incoming), autoMixEnabled: autoMixEnabled,
                crossfadeEnabled: !autoMixEnabled, crossfadeSeconds: 6, aiEffectActive: false
            )
            #expect(coordinator.state.isPreparing == shouldPrepare)
        }
    }

    @Test("A duration correction cancels a mix already in preparation", arguments: [false, true])
    @MainActor
    func correctedOutgoingDurationCancelsMix(autoMixEnabled: Bool) throws {
        let coordinator = TransitionCoordinator()
        defer { coordinator.reset() }
        let outgoing = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"outgoing","title":"Outgoing"}"#.utf8))
        let incoming = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"incoming","title":"Incoming"}"#.utf8))
        let target = PlaybackQueueState.Entry(song: incoming)

        for duration in [45.0, 44.9] {
            coordinator.poll(
                currentTime: 39, totalDuration: duration, currentSong: outgoing, target: target,
                autoMixEnabled: autoMixEnabled, crossfadeEnabled: !autoMixEnabled,
                crossfadeSeconds: 6, aiEffectActive: false
            )
            #expect(coordinator.state.isPreparing == (duration == 45))
        }
        #expect(coordinator.pendingPlan == nil)
    }

    @Test("Incoming audio length determines eligibility without duration metadata", arguments: [false, true], [44.9, 45.0])
    @MainActor
    func actualIncomingDurationDeterminesEligibility(autoMixEnabled: Bool, incomingDuration: Double) async throws {
        let coordinator = TransitionCoordinator()
        let id = "transition-duration-\(UUID())"
        let directory = AudioCacheStore.ensureSongDirectory(for: id)
        let file = directory.appendingPathComponent("main.wav")
        defer {
            coordinator.reset()
            AudioCacheStore.removeSongCache(for: id)
        }
        try writeSilentWave(to: file, frames: Int(incomingDuration * 8_000))
        let incoming = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"\#(id)","title":"Incoming"}"#.utf8))
        let outgoing = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"outgoing","title":"Outgoing","duration":60}"#.utf8))
        try #require(incoming.duration == 0)
        coordinator.poll(
            currentTime: 40, totalDuration: 60, currentSong: outgoing, target: PlaybackQueueState.Entry(song: incoming),
            autoMixEnabled: autoMixEnabled, crossfadeEnabled: !autoMixEnabled, crossfadeSeconds: 6, aiEffectActive: false
        )
        try #require(coordinator.state.isPreparing)
        let deadline = ContinuousClock.now + .seconds(5)
        while coordinator.state.isPreparing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!coordinator.state.isPreparing)
        #expect(coordinator.pendingPlan?.nextFileURL == (incomingDuration == 45 ? file : nil))
    }

    @Test("Auto Mix uses a beat-aligned equal-power fade for close tempos")
    func autoMixFadeForCloseTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 124)

        #expect(result.duration == 8.0)
        #expect(isEqualPower(result.style))
    }

    @Test("Auto Mix uses a short linear cut for incompatible tempos")
    func autoMixFadeForDistantTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 87)

        #expect(result.duration == 1.5)
        #expect(isLinear(result.style))
    }

    @Test("Auto Mix falls back to a music-style crossfade when BPM is unavailable")
    func autoMixFadeWithoutBPM() {
        let result = TransitionCoordinator.computeFade(outBPM: nil, inBPM: 120)

        #expect(result.duration == 6.0)
        #expect(isEqualPower(result.style))
    }

    @Test("A transition predownloads a song that has never been cached")
    @MainActor
    func predownloadCreatesColdCacheDirectory() async throws {
        let songID = "transition-cold-\(UUID())"
        let cache = AudioCacheStore.files(for: songID).directory
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("\(songID).wav")
        let remoteURL = try #require(URL(string: "https://example.invalid/\(fixture.lastPathComponent)"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransitionAudioProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: cache)
            try? FileManager.default.removeItem(at: fixture)
        }

        try writeSilentWave(to: fixture, frames: 16_000)
        try #require(!FileManager.default.fileExists(atPath: cache.path))

        let predownload = PredownloadSession(songID: songID, expectedDuration: 2, remoteURL: remoteURL, session: session)
        await withCheckedContinuation { continuation in
            predownload.onCompletion = { continuation.resume() }
            Task.detached { predownload.start(from: remoteURL) }
        }
        #expect(AudioCacheStore.playableMainURL(for: songID, expectedRemoteURL: remoteURL, expectedDuration: 2) != nil)
    }

    @Test("Auto Mix rejects invalid cached tempos")
    func autoMixFadeWithInvalidBPM() {
        let zero = TransitionCoordinator.computeFade(outBPM: 0, inBPM: 120)
        let nonFinite = TransitionCoordinator.computeFade(outBPM: .infinity, inBPM: 120)

        #expect(zero.duration == 6.0)
        #expect(isEqualPower(zero.style))
        #expect(nonFinite.duration == 6.0)
        #expect(isEqualPower(nonFinite.style))
    }

    @Test("Harmonic BPM comparison treats double-time tempos as compatible")
    func harmonicBPMDifferenceUsesDoubleTime() {
        #expect(TransitionCoordinator.harmonicBPMDifference(90, 180) == 0)
        #expect(TransitionCoordinator.harmonicBPMDifference(120, 62) == 4)
    }

    private func writeSilentWave(to url: URL, frames: Int) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = try #require(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0, count: frames)
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    private func isEqualPower(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .equalPower = style { return true }
        return false
    }

    private func isLinear(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .linear = style { return true }
        return false
    }
}

// URLProtocol owns the request and client callbacks. The fixture is immutable
// after the test starts the session.
// swiftlint:disable:next unchecked_sendable
nonisolated private final class TransitionAudioProtocol: URLProtocol, @unchecked Sendable {
    override static func canInit(with _: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let payload = try? Data(contentsOf: URL.temporaryDirectory.appendingPathComponent(url.lastPathComponent)),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/wav"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
