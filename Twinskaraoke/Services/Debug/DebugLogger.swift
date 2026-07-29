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
