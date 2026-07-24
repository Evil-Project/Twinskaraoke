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
        player.completionHandler = { completionCount += 1 }
        player.play(from: player.duration)
        await Task.yield()

        #expect(!player.isPlaying)
        #expect(completionCount == 1)
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
