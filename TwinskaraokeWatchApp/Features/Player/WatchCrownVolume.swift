import Foundation

/// Where the Digital Crown sits versus how loud the watch is.
///
/// Volume follows the Crown's reported position: as the position rises the
/// watch gets louder, so scrolling down — the direction that raises it — turns
/// the music up.
///
/// This lives on its own, away from the view, because the direction was wrong
/// in shipped builds several times over and every correction was argued from an
/// impression of a moving control. Stated as arithmetic it can be pinned by a
/// test that runs in milliseconds and needs no wrist, which is what
/// `WatchCrownVolumeTests` does.
///
/// What no test here can establish is which way a physical Crown turns to raise
/// the position. `XCUIDevice.rotateDigitalCrown(delta:)` raises it for a
/// positive delta, and that convention is not a watch on an arm — a UI test
/// built on it confirmed whichever mapping happened to be shipped, three times
/// on three devices, while the volume was audibly backwards. That test has been
/// deleted rather than re-pointed, and the direction below comes from a reading
/// taken off a real Crown.
enum WatchCrownVolume {
    /// Where to seat the Crown so it points at `volume`.
    static func position(forVolume volume: Double) -> Double {
        clamped(volume)
    }

    /// How loud `position` means.
    static func volume(forPosition position: Double) -> Double {
        clamped(position)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
