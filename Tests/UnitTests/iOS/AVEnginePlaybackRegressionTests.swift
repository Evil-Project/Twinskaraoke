import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import Twinskaraoke

@Suite("AVEngine playback regressions", .serialized)
@MainActor
struct AVEnginePlaybackRegressionTests {
    @Test("Stopping a scheduled player does not report natural playback end")
    func teardownCompletionIsSuppressed() throws {
        let sourceURL = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        let file = try AVAudioFile(forReading: sourceURL)

        var completionCount = 0
        player.completionHandler = { completionCount += 1 }
        try player.load(file: file)
        let scheduledGeneration = player.scheduleGenerationForTesting
        player.stop()
        player.deliverCompletionForTesting(scheduledGeneration: scheduledGeneration)

        #expect(player.scheduleGenerationForTesting != scheduledGeneration)
        #expect(completionCount == 0)
    }

    @Test("File-backed playback preserves the source processing format")
    func nativeSourceFormatIsRetained() throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        try player.load(file: AVAudioFile(forReading: sourceURL))

        #expect(player.loadedFileFormatForTesting?.sampleRate == 48_000)
        #expect(player.loadedFileFormatForTesting?.channelCount == 2)
        #expect(abs(player.duration - 2) < 0.01)
    }

    @Test("Starting at end of file reports completion without phantom playback")
    func endOfFileStartCompletes() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let player = SimpleAudioPlayer()
        try player.load(file: AVAudioFile(forReading: sourceURL))

        var completionCount = 0
        await confirmation("end-of-file completion fires once", expectedCount: 1) { completion in
            // The completion is delivered through a MainActor task hop, so the
            // body must suspend until it fires: confirmation() checks the
            // count as soon as its body returns and does not wait on its own.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var didResume = false
                player.completionHandler = {
                    completionCount += 1
                    completion()
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume()
                }
                player.play(from: player.duration)
            }
        }

        #expect(!player.isPlaying)
        #expect(completionCount == 1)
    }

    @Test("Seek while paused then resume continues from the seek target")
    func pausedSeekThenResumeKeepsPosition() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 10, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let engine = AVEnginePlayback()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        engine.pause()
        #expect(engine.seek(to: 5))
        // The seek must not leave the decks playing behind the paused facade.
        #expect(!engine.isPlaying)
        #expect(abs(engine.currentTime - 5) < 0.5)

        // Regression: resume used to fall through to play(from: 0) because
        // the seek's internal stop()/play() had cleared the paused state.
        engine.resume()
        #expect(engine.currentTime >= 4.5)
        engine.stop()
    }

    @Test("Crossfade promotes the incoming track and clears transition state")
    func crossfadeCompletesHandoff() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let incomingURL = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: incomingURL)
        }

        let engine = AVEnginePlayback()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        await confirmation("crossfade completes", expectedCount: 1) { completion in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                engine.onCrossfadeCompleted = {
                    completion()
                    continuation.resume()
                }
                engine.beginCrossfade(url: incomingURL, duration: 0.5, ramp: .linear)
            }
        }

        #expect(!engine.isCrossfading)
        #expect(engine.currentURL == incomingURL)
        #expect(!engine.isCrossfadePending)
        engine.stop()
    }

    @Test("An unavailable incoming file leaves the outgoing song playing")
    func crossfadeLoadFailureDoesNotEndOutgoingPlayback() async throws {
        let sourceURL = try makeSilentWaveFile(duration: 4, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let missingURL = sourceURL.appendingPathExtension("missing")
        let engine = AVEnginePlayback()
        defer { engine.stop() }
        await withCheckedContinuation { continuation in
            engine.play(url: sourceURL, onReady: { continuation.resume() })
        }

        var playbackErrors = 0
        engine.onPlaybackError = { _ in playbackErrors += 1 }
        engine.beginCrossfade(url: missingURL, duration: 1, ramp: .linear)
        try await Task.sleep(for: .milliseconds(250))

        #expect(playbackErrors == 0)
        #expect(!engine.isCrossfadePending)
        #expect(engine.currentURL == sourceURL)
        #expect(engine.isPlaying)
    }

    @Test("A late crossfade reuses the incoming load and keeps the mixer audible")
    func lateCrossfadeReusesLoad() async throws {
        let outgoing = try makeSilentWaveFile(duration: 2, sampleRate: 48_000, tone: 440)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000, tone: 660)
        let load = GatedLoad()
        let engine = AVEnginePlayback(crossfadeFileLoader: load.open)
        let capture = MixerCapture()
        let mixer = engine.crossfadeMixerForTesting
        mixer.installTap(onBus: 0, bufferSize: 256, format: nil) { @Sendable buffer, _ in
            capture.append(buffer)
        }
        defer {
            load.release()
            mixer.removeTap(onBus: 0)
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }

        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        engine.preloadCrossfade(url: incoming)
        try await waitUntil { load.count == 1 && engine.currentTime >= 1.8 }
        var scheduledDuration: TimeInterval?
        engine.onCrossfadeScheduled = { scheduledDuration = $0 }
        engine.onPlaybackEnded = { [weak engine] in
            engine?.finishPreparedCrossfade(to: incoming)
        }
        engine.beginCrossfade(url: incoming, duration: 0.6, ramp: .linear)
        load.release()
        try await waitUntil { engine.currentURL == incoming && engine.currentTime >= 0.2 }
        #expect(load.count == 1)
        #expect(try #require(scheduledDuration) < 0.6)
        let windows = capture.audibleWindows
        let first = try #require(windows.firstIndex(of: true))
        let last = try #require(windows.lastIndex(of: true))
        #expect(windows[first ... last].allSatisfy { $0 })
    }

    @Test("A ready incoming deck can be promoted at natural end without scheduling a fade")
    func readyDeckAtNaturalEnd() async throws {
        let outgoing = try makeSilentWaveFile(duration: 1.5, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let engine = AVEnginePlayback()
        defer {
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        var scheduled = false
        var handedOff = false
        engine.onCrossfadeScheduled = { _ in scheduled = true }
        engine.onPlaybackEnded = { [weak engine] in
            handedOff = engine?.finishPreparedCrossfade(to: incoming) == true
        }
        engine.beginCrossfade(url: incoming, duration: 1, ramp: .linear, remainingTime: { 0 })
        try await waitUntil { handedOff }
        #expect(!scheduled)
        #expect(engine.currentURL == incoming)
        #expect(!engine.isCrossfadePending)
    }

    @Test("Natural end is delivered while the incoming load is pending and cancellation fences its result")
    func lateLoadCanBeCancelledAtNaturalEnd() async throws {
        let outgoing = try makeSilentWaveFile(duration: 1.5, sampleRate: 48_000)
        let incoming = try makeSilentWaveFile(duration: 2, sampleRate: 48_000)
        let load = GatedLoad()
        let engine = AVEnginePlayback(crossfadeFileLoader: load.open)
        defer {
            load.release()
            engine.stop()
            for url in [outgoing, incoming] { try? FileManager.default.removeItem(at: url) }
        }
        await withCheckedContinuation { continuation in
            engine.play(url: outgoing, onReady: { continuation.resume() })
        }
        var advances = 0
        engine.onPlaybackEnded = { [weak engine] in
            guard let engine else { return }
            #expect(!engine.finishPreparedCrossfade(to: incoming))
            engine.cancelCrossfade()
            advances += 1
        }
        engine.beginCrossfade(url: incoming, duration: 1, ramp: .linear)
        try await waitUntil { load.count == 1 && advances == 1 }
        var schedules = 0
        engine.onCrossfadeScheduled = { _ in schedules += 1 }
        engine.beginCrossfade(url: incoming, duration: 0.5, ramp: .linear, remainingTime: { 0 })
        try await waitUntil { load.count == 2 }
        load.release()
        load.release()
        var promoted = false
        try await waitUntil {
            if !promoted { promoted = engine.finishPreparedCrossfade(to: incoming) }
            return promoted
        }
        #expect(engine.currentURL == incoming)
        #expect(schedules == 0)
        #expect(advances == 1)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate())
    }

    private func makeSilentWaveFile(duration: TimeInterval, sampleRate: Double, tone: Double? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-regression-\(UUID().uuidString).wav")
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        for channel in 0 ..< 2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0 ..< Int(frameCount) {
                samples[frame] = tone.map { Float(0.2 * sin(2 * .pi * $0 * Double(frame) / sampleRate)) } ?? 0
            }
        }
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        try writer.write(from: buffer)
        return url
    }
}

private nonisolated final class GatedLoad: Sendable {
    private let opens = Mutex(0)
    private let gate = DispatchSemaphore(value: 0)

    var count: Int { opens.withLock { $0 } }

    func open(_ url: URL) throws -> AVAudioFile {
        opens.withLock { $0 += 1 }
        _ = gate.wait(timeout: .now() + 5)
        return try AVAudioFile(forReading: url)
    }

    func release() { gate.signal() }
}

private nonisolated final class MixerCapture: Sendable {
    private let samples = Mutex<[Float]>([])

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.withLock { $0.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))) }
    }

    var audibleWindows: [Bool] {
        let captured = samples.withLock { $0 }
        // Five milliseconds per window at 48 kHz, with a -60 dBFS threshold.
        return stride(from: 0, to: max(0, captured.count - 239), by: 240).map { start in
            captured[start ..< start + 240].reduce(0.0) { $0 + Double($1 * $1) } / 240 > 0.000001
        }
    }
}
