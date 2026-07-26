import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Vocal separator regressions", .serialized)
struct VocalSeparatorRegressionTests {
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
