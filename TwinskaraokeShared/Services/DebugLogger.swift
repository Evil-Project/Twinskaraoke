import Foundation
import os.log

nonisolated enum LogCategory: String {
    case cache = "Cache"
    case ai = "AI"
    case playback = "Playback"
    case separation = "Separation"
    case network = "Network"
    case ui = "UI"

    // Cached per category: this is read on every log call, and constructing an
    // OSLog handle each time throws away the one the system already made.
    var osLog: OSLog {
        switch self {
        case .cache: Self.cacheLog
        case .ai: Self.aiLog
        case .playback: Self.playbackLog
        case .separation: Self.separationLog
        case .network: Self.networkLog
        case .ui: Self.uiLog
        }
    }

    private static let subsystem = "com.xiaoyuan151.Twinskaraoke"
    private static let cacheLog = OSLog(subsystem: subsystem, category: LogCategory.cache.rawValue)
    private static let aiLog = OSLog(subsystem: subsystem, category: LogCategory.ai.rawValue)
    private static let playbackLog = OSLog(subsystem: subsystem, category: LogCategory.playback.rawValue)
    private static let separationLog = OSLog(subsystem: subsystem, category: LogCategory.separation.rawValue)
    private static let networkLog = OSLog(subsystem: subsystem, category: LogCategory.network.rawValue)
    private static let uiLog = OSLog(subsystem: subsystem, category: LogCategory.ui.rawValue)
}

nonisolated enum DebugLogger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "nk.debugLogging")
    }

    private static let logQueue = DispatchQueue(label: "nk.debugLogger", qos: .utility)
    // Only accessed on logQueue.
    private nonisolated(unsafe) static var recentLogs: [String] = []
    private static let maxStoredLogs = 500

    static func log(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: String = #fileID,
        line: Int = #line
    ) {
        guard isEnabled else { return }
        let msg = message()
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let entry = "[\(category.rawValue)] \(timestamp) \(fileName):\(line) — \(msg)"

        os_log("%{public}@", log: category.osLog, type: .debug, entry)

        logQueue.async {
            recentLogs.append(entry)
            if recentLogs.count > maxStoredLogs {
                recentLogs.removeFirst(recentLogs.count - maxStoredLogs)
            }
        }
    }

    static func exportLogs() -> String {
        logQueue.sync { recentLogs.joined(separator: "\n") }
    }

    /// Writes the buffer to a text file for sharing. The buffer lives only in
    /// memory and only fills while Debug Logging is on, so it is often empty
    /// right after a relaunch; the header says so instead of producing an
    /// empty file that share targets silently drop.
    static func exportLogFile(
        in directory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date()
    ) throws -> URL {
        let entries = logQueue.sync { recentLogs }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "Twinskaraoke debug log",
            "Exported: \(now.ISO8601Format())",
            "Version: \(version) (\(build))",
            "Entries: \(entries.count)",
        ]
        if entries.isEmpty {
            lines.append("No entries. Logging records only while Debug Logging is on, and the buffer is cleared when the app quits.")
        }
        lines.append("")
        lines.append(contentsOf: entries)

        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.omitted)
            .time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = directory.appendingPathComponent("Twinskaraoke-debug-log-\(stamp).txt")
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
        return url
    }

    static func clearLogs() {
        logQueue.async { recentLogs.removeAll() }
    }
}
