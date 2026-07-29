import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

/// The Crown-to-volume mapping, pinned at its endpoints.
///
/// This replaces a UI test that spent twenty seconds per run turning a
/// simulated Crown and drew the wrong conclusion every time: the Simulator's
/// rotation sign is not a wrist's, so it kept confirming whichever mapping was
/// currently shipped. These endpoints came off a real watch, cost no seconds,
/// and cannot quietly agree with a regression.
@Suite("Watch crown volume mapping")
struct WatchCrownVolumeTests {
    @Test("Crown position 0 is silence")
    func bottomOfTravelIsSilent() {
        #expect(WatchCrownVolume.volume(forPosition: 0) == 0)
        #expect(WatchCrownVolume.position(forVolume: 0) == 0)
    }

    @Test("Crown position 1 is full volume")
    func topOfTravelIsLoud() {
        #expect(WatchCrownVolume.volume(forPosition: 1) == 1)
        #expect(WatchCrownVolume.position(forVolume: 1) == 1)
    }

    /// The direction, stated the way it was specified: a rising Crown position
    /// is a rising volume. Everything else here would still pass if the mapping
    /// were inverted, so this is the assertion that actually holds the fix.
    @Test("A rising Crown position raises the volume")
    func risingPositionRaisesVolume() {
        #expect(
            WatchCrownVolume.volume(forPosition: 0.7)
                > WatchCrownVolume.volume(forPosition: 0.3)
        )
    }

    /// The two halves seat the Crown and read it back, so drift between them
    /// would leave the handle pointing somewhere other than the volume it set.
    @Test("Seating and reading back are exact inverses")
    func roundTripsExactly() {
        for step in 0...20 {
            let volume = Double(step) / 20
            let position = WatchCrownVolume.position(forVolume: volume)
            #expect(abs(WatchCrownVolume.volume(forPosition: position) - volume) < 0.000_001)
        }
    }

    /// `digitalCrownRotation` is bounded to 0...1, but volume also arrives from
    /// restored defaults, which have no such guarantee.
    @Test("Out-of-range input is clamped rather than wrapped")
    func clampsRatherThanWraps() {
        #expect(WatchCrownVolume.volume(forPosition: 1.4) == 1)
        #expect(WatchCrownVolume.volume(forPosition: -0.3) == 0)
        #expect(WatchCrownVolume.position(forVolume: 1.4) == 1)
        #expect(WatchCrownVolume.position(forVolume: -0.3) == 0)
    }
}
