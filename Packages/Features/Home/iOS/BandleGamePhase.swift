import Foundation

enum BandleGamePhase: Equatable {
    case idle
    case loading
    case ready
    case starting
    case playing
    case submitting
    case completed

    var isBusy: Bool {
        switch self {
        case .loading, .starting, .submitting: true
        case .idle, .ready, .playing, .completed: false
        }
    }
}
