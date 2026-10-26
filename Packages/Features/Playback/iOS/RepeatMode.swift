import Foundation

/// `.all` loops a selected collection, or the song selected directly. `.one`
/// replays the current song once before switching itself off. Raw case names
/// stay compatible with saved sessions, widget snapshots and watch sync.
nonisolated enum RepeatMode: Equatable, Sendable, Codable {
    case off, all, one
    var symbol: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var isActive: Bool {
        self != .off
    }

    func next() -> RepeatMode {
        switch self {
        case .off: .one
        case .one: .all
        case .all: .off
        }
    }
}
