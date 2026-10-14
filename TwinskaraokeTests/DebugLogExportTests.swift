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

    @Test func entryTimestampsStayTwentyFourHour() throws {
        // The formatter is private; its output is checked through an entry.
        let key = "nk.debugLogging"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        DebugLogger.log("timestamp probe", category: .ui)
        let entry = try #require(DebugLogger.exportLogs()
            .split(separator: "\n").last { $0.hasSuffix("timestamp probe") })
        #expect(!entry.contains("AM") && !entry.contains("PM"))
        #expect(entry.wholeMatch(of: /\[UI\] \d{2}:\d{2}:\d{2}\.\d{3} .*/) != nil)
    }
}
