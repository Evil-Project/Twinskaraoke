import CoreGraphics

/// The arithmetic behind the full-screen player's drag-to-dismiss, kept apart
/// from the view so it can be tested without a screen.
///
/// This exists because the dependency it replaces got the decision wrong in a
/// way that was not tunable from the outside. LNPopupController's snap style
/// decided dismissal from absolute position alone — `popupSnapPercent = 0.32`
/// of the container, roughly 290pt on this device — and then discarded velocity
/// entirely when the finger lifted, so a 3000pt/s flick and a release at rest
/// from the same point produced the same outcome. Its drag style read velocity
/// but only as a sign test. Neither ever projected where the gesture was
/// *going*, which is what makes a short, fast flick read as decisive to a
/// person and as "nowhere near far enough" to the code.
///
/// So the decision here is made on the projection alone.
///
/// It is tempting to add "…or it travelled far enough anyway" as a second
/// clause, and the first draft of this did. It is wrong. For any drag still
/// moving downward the projection is already at or beyond the translation, so
/// the distance clause can never be the one that fires — it is unreachable.
/// The only drags it *would* catch are the ones travelling back up at release:
/// pull the player down two thirds of the way, think better of it, and flick
/// back up. A distance clause dismisses that. Everywhere else in iOS, and in
/// LNPopupController's own drag style, a reversal cancels. One term gets all
/// four cases right; two terms get the fourth one wrong.
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

    /// UIScrollView's rubberband constant, by way of LNPopupController, which
    /// borrowed the same formula. One of the few things in that library worth
    /// keeping verbatim — it is what makes over-travel feel like resistance
    /// rather than a wall.
    static let rubberbandConstant: CGFloat = 0.55

    /// `f(x, d, c) = (x · d · c) / (d + c · x)` — asymptotic in `x`, so the
    /// result approaches but never reaches `limit · c` no matter how far the
    /// finger goes.
    ///
    /// - Parameters:
    ///   - distance: Travel beyond the natural end of the range. Negative
    ///     input mirrors, so callers do not have to special-case direction.
    ///   - limit: The dimension the resistance is scaled against, normally the
    ///     player's height.
    static func rubberband(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        guard distance >= 0 else { return -rubberband(-distance, limit: limit) }
        return (distance * limit * rubberbandConstant) / (limit + rubberbandConstant * distance)
    }

    /// How far to actually move the player for a given finger translation.
    ///
    /// Downward travel tracks the finger one-to-one — the player is going that
    /// way, and anything less feels like lag. Upward travel is rubberbanded,
    /// because there is nothing above the open player to reveal; the give is
    /// there only so the gesture does not feel dead against a stop.
    static func dragOffset(forTranslation translation: CGFloat, height: CGFloat) -> CGFloat {
        translation >= 0 ? translation : rubberband(translation, limit: height)
    }

    /// The presentation progress a given offset corresponds to: 1 with the
    /// player fully open, 0 with it fully clear of the screen.
    static func progress(forOffset offset: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 1 }
        return Double(min(1, max(0, 1 - offset / height)))
    }

    /// Whether a released drag should dismiss the player.
    ///
    /// - Parameters:
    ///   - translation: Where the finger actually got to, positive downward.
    ///     Only used to reject drags that never went down at all; the decision
    ///     itself is the projection's.
    ///   - predictedTranslation: `DragGesture.Value.predictedEndTranslation`,
    ///     the system's own projection of where the drag would come to rest if
    ///     released now and allowed to decelerate. Consulting it is the entire
    ///     fix — see the type's documentation.
    ///   - height: The player's height.
    static func shouldDismiss(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        height: CGFloat
    ) -> Bool {
        guard height > 0, translation > 0 else { return false }
        return predictedTranslation > height * commitProjectionFraction
    }
}
