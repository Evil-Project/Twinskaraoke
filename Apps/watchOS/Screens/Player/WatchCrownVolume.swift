import Foundation
enum WatchCrownVolume {
    static func position(forVolume volume: Double) -> Double {
        clamped(volume)
    }
    static func volume(forPosition position: Double) -> Double {
        clamped(position)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
