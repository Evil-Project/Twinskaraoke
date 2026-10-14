import Foundation
import Testing
@testable import Twinskaraoke

struct DebugLogExportTests {
    @Test func exportedFileIsNeverEmptyAndCarriesAHeader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try DebugLogger.exportLogFile(in: directory, now: Date(timeIntervalSince1970: 0))
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(url.pathExtension == "txt")
        #expect(url.lastPathComponent.hasPrefix("Twinskaraoke-debug-log-19700101"))
        #expect(text.hasPrefix("Twinskaraoke debug log\n"))
        #expect(text.contains("Entries: "))
    }
}
