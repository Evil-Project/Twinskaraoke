import Foundation

enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case bass = "Bass Boost"
    case treble = "Treble Boost"
    case vocal = "Vocal"
    case rock = "Rock"
    case pop = "Pop"
    case jazz = "Jazz"
    case electronic = "Electronic"
    case classical = "Classical"
    case hiphop = "Hip-Hop"
    case loudness = "Loudness"
    case custom = "Custom"

    var id: String {
        rawValue
    }

    var gains: [Float] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: [10, 8, 5, 2, 0, 0, 0, 0, 0, 0]
        case .treble: [0, 0, 0, 0, 0, 2, 4, 6, 8, 10]
        case .vocal: [-2, -1, 0, 3, 6, 6, 4, 2, 0, -1]
        case .rock: [5, 4, 2, 0, -2, -1, 2, 4, 5, 6]
        case .pop: [-1, 2, 4, 5, 3, 0, -1, 0, 2, 3]
        case .jazz: [3, 2, 0, 2, 4, 4, 2, 3, 4, 3]
        case .electronic: [6, 5, 2, 0, -2, 2, 1, 4, 6, 7]
        case .classical: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]
        case .hiphop: [7, 6, 3, 1, 0, 0, 1, 2, 4, 3]
        case .loudness: [8, 5, 0, -2, -4, -2, 0, 3, 6, 8]
        case .custom: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}
