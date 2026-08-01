import Foundation

enum RadioLiveStatusPresentation: Equatable, Sendable {
    case ready
    case buffering
    case onAir

    init(isRadioMode: Bool, isPlaying: Bool, isBuffering: Bool) {
        if isRadioMode, isBuffering {
            self = .buffering
        } else if isRadioMode, isPlaying {
            self = .onAir
        } else {
            self = .ready
        }
    }

    var isActive: Bool {
        self != .ready
    }

    var systemImage: String {
        switch self {
        case .ready: "dot.radiowaves.left.and.right"
        case .buffering: "arrow.triangle.2.circlepath"
        case .onAir: "speaker.wave.2.fill"
        }
    }

    var title: String {
        switch self {
        case .ready: "Live Ready"
        case .buffering: "Connecting"
        case .onAir: "On Air"
        }
    }

    var badgeText: String {
        switch self {
        case .ready: "READY"
        case .buffering: "CONNECTING"
        case .onAir: "LIVE"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready: "Live radio ready"
        case .buffering: "Live radio connecting"
        case .onAir: "Live radio on air"
        }
    }
}
