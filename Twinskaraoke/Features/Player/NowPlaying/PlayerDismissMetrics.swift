import CoreGraphics
nonisolated enum PlayerDismissMetrics {
    /// Opening starts in a small bottom accessory: it should not require the
    /// quarter-screen pull used to dismiss the full player. Still decide from
    /// projection so reversing direction can cancel, and reject tiny jitter.
    static func shouldOpen(translation: CGFloat, predictedTranslation: CGFloat, height: CGFloat) -> Bool {
        guard height > 0, translation <= -20 else { return false }
        return -predictedTranslation >= min(80, height * 0.1)
    }

    static func openingProgress(translation: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 0 }
        return Double(min(1, max(0, -translation / height)))
    }
    /// How far the drag must be *projected* to land, as a fraction of the
    /// player's height.
    ///
    /// At 0.25 a slow, deliberate pull commits about a quarter of the way down
    /// — near LNPopupController's own drag-style threshold of 0.2, which was
    /// the sane half of that library — while a flick of barely 120pt commits
    /// immediately, because the projection carries it far past the mark.
    static let commitProjectionFraction: CGFloat = 0.25
    static let rubberbandConstant: CGFloat = 0.55
    static func rubberband(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        guard distance >= 0 else { return -rubberband(-distance, limit: limit) }
        return (distance * limit * rubberbandConstant) / (limit + rubberbandConstant * distance)
    }
    static func dragOffset(forTranslation translation: CGFloat, height: CGFloat) -> CGFloat {
        translation >= 0 ? translation : rubberband(translation, limit: height)
    }
    static func progress(forOffset offset: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 1 }
        return Double(min(1, max(0, 1 - offset / height)))
    }
    static func shouldDismiss(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        height: CGFloat
    ) -> Bool {
        guard height > 0, translation > 0 else { return false }
        return predictedTranslation > height * commitProjectionFraction
    }
}
