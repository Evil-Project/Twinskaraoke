import AVFoundation
import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Vocal separator regressions", .serialized)
struct VocalSeparatorRegressionTests {
    @Test("Concurrent trimming produces a playable WAV with the requested remaining duration")
    func trimsAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        let output = directory.appendingPathComponent("trimmed.wav")
        try Self.writeFixture(to: source)
        try await VocalSeparator.trimForTesting(source: source, from: 1, to: output)
        let result = try AVAudioFile(forReading: output)
        let duration = Double(result.length) / result.processingFormat.sampleRate
        #expect(abs(duration - 1) < 0.05)
        #expect(result.processingFormat.channelCount == 1)
    }

    @Test("An already-cancelled trim cannot remove an existing output")
    func cancelledTrimPreservesOutput() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let existing = Data("existing output".utf8)
        try existing.write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await VocalSeparator.trimForTesting(source: output, from: 0, to: output)
        }
        do {
            try await task.value
            Issue.record("Expected cancellation before touching the output")
        } catch is CancellationError {
        }
        #expect(try Data(contentsOf: output) == existing)
    }

    private static func writeFixture(to url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200))
        buffer.frameLength = buffer.frameCapacity
        let samples = try #require(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.1)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @Test("A stale job cannot finish or clear its replacement")
    func staleJobCannotFinishReplacement() {
        var ownership = SeparationJobOwnership()
        let staleID = UUID()
        let replacementID = UUID()

        ownership.begin(id: staleID)
        ownership.begin(id: replacementID)

        let staleFinished = ownership.finish(staleID)
        #expect(!staleFinished)
        #expect(ownership.owns(replacementID))
        let replacementFinished = ownership.finish(replacementID)
        #expect(replacementFinished)
        #expect(ownership.activeID == nil)
    }

    @Test("Stale cleanup cannot delete replacement output files")
    func staleCleanupCannotDeleteReplacementOutputs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("separation-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stale = VocalSeparator.separationOutputURLs(
            in: directory,
            songID: "same-song",
            jobID: UUID()
        )
        let replacement = VocalSeparator.separationOutputURLs(
            in: directory,
            songID: "same-song",
            jobID: UUID()
        )

        for url in [stale.vocals, stale.instruments, replacement.vocals, replacement.instruments] {
            try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        }

        // The production failure path cleans up only the failing job's own
        // staging URLs, which are namespaced by that job's ID.
        VocalSeparator.cleanupTmpFilesForTesting([stale.vocals, stale.instruments])

        #expect(!FileManager.default.fileExists(atPath: stale.vocals.path))
        #expect(!FileManager.default.fileExists(atPath: stale.instruments.path))
        #expect(FileManager.default.fileExists(atPath: replacement.vocals.path))
        #expect(FileManager.default.fileExists(atPath: replacement.instruments.path))
    }

    @Test("Failed publication restores the previous stem pair")
    func failedPublicationRestoresPreviousStems() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stem-publication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let previousVocals = directory.appendingPathComponent("vocals.wav")
        let previousInstruments = directory.appendingPathComponent("instruments.wav")
        let stagedVocals = directory.appendingPathComponent("staged-vocals.wav")
        let missingStagedInstruments = directory.appendingPathComponent("missing-instruments.wav")
        let previousVocalsData = Data("previous vocals".utf8)
        let previousInstrumentsData = Data("previous instruments".utf8)

        try previousVocalsData.write(to: previousVocals)
        try previousInstrumentsData.write(to: previousInstruments)
        try Data("replacement vocals".utf8).write(to: stagedVocals)

        do {
            try VocalSeparator.publishStemFilesForTesting(
                vocalsSource: stagedVocals,
                instrumentsSource: missingStagedInstruments,
                vocalsDestination: previousVocals,
                instrumentsDestination: previousInstruments
            )
            Issue.record("Expected publication to fail when the second staged stem is missing")
        } catch {}

        #expect(try Data(contentsOf: previousVocals) == previousVocalsData)
        #expect(try Data(contentsOf: previousInstruments) == previousInstrumentsData)
    }
}
