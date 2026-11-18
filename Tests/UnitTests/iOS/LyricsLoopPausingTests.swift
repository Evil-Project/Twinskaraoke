import SwiftUI
import Testing
@testable import Twinskaraoke

/// The lyrics' looping dots and the translation ring tick at the full display
/// rate, and the full-screen player stays mounted when closed. They may only
/// tick while someone can see them.
@MainActor
struct LyricsLoopPausingTests {
    @Test func theDotsLoopWhenActiveVisibleAndOnScreen() {
        #expect(LyricsBouncingDots.shouldAnimateLoop(
            isActive: true, isPaused: false, isVisible: true, reduceEffects: false, scenePhase: .active
        ))
    }

    @Test(arguments: [
        (isActive: false, isPaused: false, isVisible: true, reduceEffects: false, scenePhase: ScenePhase.active),
        (isActive: true, isPaused: true, isVisible: true, reduceEffects: false, scenePhase: ScenePhase.active),
        (isActive: true, isPaused: false, isVisible: false, reduceEffects: false, scenePhase: ScenePhase.active),
        (isActive: true, isPaused: false, isVisible: true, reduceEffects: true, scenePhase: ScenePhase.active),
        (isActive: true, isPaused: false, isVisible: true, reduceEffects: false, scenePhase: ScenePhase.inactive),
        (isActive: true, isPaused: false, isVisible: true, reduceEffects: false, scenePhase: ScenePhase.background),
    ])
    func theDotsStopWhenAnyConditionFails(
        isActive: Bool, isPaused: Bool, isVisible: Bool, reduceEffects: Bool, scenePhase: ScenePhase
    ) {
        #expect(!LyricsBouncingDots.shouldAnimateLoop(
            isActive: isActive,
            isPaused: isPaused,
            isVisible: isVisible,
            reduceEffects: reduceEffects,
            scenePhase: scenePhase
        ))
    }

    @Test func theTranslationRingSpinsOnlyWhileSeen() {
        #expect(LyricsTranslationSpinner.shouldSpin(isPaused: false, isVisible: true, scenePhase: .active))
        #expect(!LyricsTranslationSpinner.shouldSpin(isPaused: true, isVisible: true, scenePhase: .active))
        #expect(!LyricsTranslationSpinner.shouldSpin(isPaused: false, isVisible: false, scenePhase: .active))
        #expect(!LyricsTranslationSpinner.shouldSpin(isPaused: false, isVisible: true, scenePhase: .background))
    }
}
