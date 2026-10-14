import Foundation
import Testing
@testable import Twinskaraoke

struct DebugLogExportTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func exportedFileIsNeverEmptyAndCarriesAHeader() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try DebugLogger.exportLogFile(in: directory, now: Date(timeIntervalSince1970: 0))
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(url.pathExtension == "txt")
        #expect(url.lastPathComponent.hasPrefix("Twinskaraoke-debug-log-19700101"))
        #expect(text.hasPrefix("Twinskaraoke debug log\n"))
        #expect(text.contains("Entries: "))
    }

    @Test func exportsInTheSameSecondDoNotReplaceEachOther() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()

        let first = try DebugLogger.exportLogFile(in: directory, now: now)
        let second = try DebugLogger.exportLogFile(in: directory, now: now)

        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func exportRemovesOnlyStaleExports() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let stale = directory.appendingPathComponent("Twinskaraoke-debug-log-old.txt")
        let recent = directory.appendingPathComponent("Twinskaraoke-debug-log-recent.txt")
        let unrelated = directory.appendingPathComponent("something-else.txt")
        for (file, age) in [(stale, 20.0 * 60), (recent, 60.0), (unrelated, 20.0 * 60)] {
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        }

        _ = try DebugLogger.exportLogFile(in: directory, now: now)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func entryTimestampsAreTwentyFourHour() throws {
        let afternoon = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 14, hour: 15, minute: 4, second: 5)))
        #expect(DebugLogger.timestamp(for: afternoon) == "15:04:05.000")
    }
}
