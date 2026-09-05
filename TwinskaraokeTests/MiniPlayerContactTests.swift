import CoreGraphics
import Testing
@testable import Twinskaraoke

struct MiniPlayerContactTests {
    @Test func heldTinyDragRemainsNearMiniPlayer() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        #expect(contact.move(to: CGPoint(x: 100, y: 794), time: 1) == .dragging)
        #expect(contact.isDragging)
        #expect(PlayerDismissMetrics.openingProgress(translation: contact.translation, height: contact.height) < 0.01)
        contact.finish(at: CGPoint(x: 100, y: 794), time: 2)
        #expect(contact.projectedTranslation == -6)
        #expect(!PlayerDismissMetrics.shouldOpen(translation: contact.translation,
                                                   predictedTranslation: contact.projectedTranslation,
                                                   height: contact.height))
    }

    @Test func coordinatesStayAnchoredToOriginalTouch() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        _ = contact.move(to: CGPoint(x: 100, y: 780), time: 0.1)
        _ = contact.move(to: CGPoint(x: 100, y: 790), time: 0.2)
        #expect(contact.translation == -10)
        #expect(contact.height == 900)
        #expect(contact.isDragging)
        #expect(contact.projectedTranslation > 0)
    }

    @Test func dragNeverTurnsBackIntoTap() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        _ = contact.move(to: CGPoint(x: 100, y: 780), time: 0.1)
        _ = contact.move(to: CGPoint(x: 100, y: 800), time: 0.2)
        contact.finish(at: CGPoint(x: 100, y: 800), time: 1)
        #expect(contact.isDragging)
        #expect(contact.translation == 0)
    }

    @Test func horizontalMovementRejectsOpening() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        #expect(contact.move(to: CGPoint(x: 120, y: 797), time: 0.1) == .rejected)
        #expect(!contact.isDragging)
    }

    @Test func missedMoveCannotBecomeTapAtRelease() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        let recognized = contact.finish(at: CGPoint(x: 100, y: 780), time: 1)
        #expect(!recognized)
    }

    @Test func shortFlickSurvivesStationaryFinalSample() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        _ = contact.move(to: CGPoint(x: 100, y: 796), time: 1)
        _ = contact.move(to: CGPoint(x: 100, y: 770), time: 1.04)
        _ = contact.move(to: CGPoint(x: 100, y: 770), time: 1.05)
        contact.finish(at: CGPoint(x: 100, y: 770), time: 1.06)
        #expect(PlayerDismissMetrics.shouldOpen(translation: contact.translation,
                                               predictedTranslation: contact.projectedTranslation,
                                               height: contact.height))
    }

    @Test func holdingShortFlickDiscardsVelocity() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        _ = contact.move(to: CGPoint(x: 100, y: 770), time: 0.04)
        contact.finish(at: CGPoint(x: 100, y: 770), time: 0.3)
        #expect(contact.projectedTranslation == -30)
        #expect(!PlayerDismissMetrics.shouldOpen(translation: contact.translation,
                                                predictedTranslation: contact.projectedTranslation,
                                                height: contact.height))
    }

    @Test func initialSidewaysJitterCanResolveUpwards() {
        var contact = MiniPlayerContact()
        contact.begin(at: CGPoint(x: 100, y: 800), time: 0, height: 900)
        #expect(contact.move(to: CGPoint(x: 105, y: 797), time: 0.02) == .waiting)
        #expect(contact.move(to: CGPoint(x: 106, y: 780), time: 0.06) == .dragging)
    }

    @Test func openingHasItsOwnReleaseThreshold() {
        for height: CGFloat in [800, 900, 1200] {
            #expect(PlayerDismissMetrics.shouldOpen(translation: -85, predictedTranslation: -85, height: height))
            #expect(PlayerDismissMetrics.shouldOpen(translation: -30, predictedTranslation: -120, height: height))
            #expect(!PlayerDismissMetrics.shouldOpen(translation: -6, predictedTranslation: -300, height: height))
            #expect(!PlayerDismissMetrics.shouldOpen(translation: -85, predictedTranslation: -20, height: height))
            #expect(!PlayerDismissMetrics.shouldOpen(translation: 30, predictedTranslation: -120, height: height))
        }
    }
}
