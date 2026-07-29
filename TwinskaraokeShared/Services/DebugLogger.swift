import Foundation
import os.log

nonisolated enum LogCategory: String {
    case cache = "Cache"
    case ai = "AI"
    case playback = "Playback"
    case separation = "Separation"
    case network = "Network"
    case ui = "UI"

    var osLog: OSLog {
        OSLog(subsystem: "com.xiaoyuan151.Twinskaraoke", category: rawValue)
    }
}

nonisolated enum DebugLogger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var isEnabled: Bool {
        #if DEBUG
            return true
        #else
            return UserDefaults.standard.bool(forKey: "nk.debugLogging")
        #endif
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

    static func clearLogs() {
        logQueue.async { recentLogs.removeAll() }
    }
}
