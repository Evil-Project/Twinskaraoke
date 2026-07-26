import AVFoundation
import Foundation
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

    private func makeSilentWaveFile(duration: TimeInterval, sampleRate: Double) throws -> URL {
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
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        try writer.write(from: buffer)
        return url
    }
}
