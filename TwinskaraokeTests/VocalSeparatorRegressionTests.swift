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
        for url in [stale.vocals, stale.instruments] {
            try FileManager.default.removeItem(at: url)
        }

        #expect(!FileManager.default.fileExists(atPath: stale.vocals.path))
        #expect(!FileManager.default.fileExists(atPath: stale.instruments.path))
        #expect(FileManager.default.fileExists(atPath: replacement.vocals.path))
        #expect(FileManager.default.fileExists(atPath: replacement.instruments.path))
    }
}
