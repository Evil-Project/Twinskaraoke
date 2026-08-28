import Testing
@testable import Twinskaraoke

@Suite("Application motion policy")
struct AppMotionTests {
    @Test("Reduce Motion follows the system setting only when enabled in-app")
    func reducedMotionPreference() {
        #expect(AppMotion.reduceMotion(systemReduceMotion: true, respectPreference: true))
        #expect(!AppMotion.reduceMotion(systemReduceMotion: true, respectPreference: false))
        #expect(!AppMotion.reduceMotion(systemReduceMotion: false, respectPreference: true))
    }

    @Test("Decorative effects pause for accessibility or Low Power Mode")
    func decorativeEffectsPolicy() {
        #expect(AppMotion.reduceDecorativeEffects(reduceMotion: true, lowPowerModeEnabled: false))
        #expect(AppMotion.reduceDecorativeEffects(reduceMotion: false, lowPowerModeEnabled: true))
        #expect(!AppMotion.reduceDecorativeEffects(reduceMotion: false, lowPowerModeEnabled: false))
    }
}
