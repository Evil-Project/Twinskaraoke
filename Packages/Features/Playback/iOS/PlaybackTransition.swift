import Foundation

/// Owns the callbacks associated with the outgoing song's transition.
@MainActor
final class PlaybackTransition {
    typealias Plan = TransitionCoordinator.TransitionPlan

    var activePlan: Plan?
    private var deadline: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    deinit {
        deadline?.cancel()
        watchdog?.cancel()
    }

    func scheduleDeadline(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        deadline?.cancel()
        deadline = schedule(after: delay, fire)
    }

    func scheduleWatchdog(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        watchdog?.cancel()
        watchdog = schedule(after: delay, fire)
    }

    func watchScheduledHandoff(
        duration: TimeInterval,
        engine: AVEnginePlayback,
        onFailure: @escaping @MainActor () -> Void
    ) {
        guard let plan = activePlan else { return }
        scheduleWatchdog(after: duration + 3) { [weak self, weak engine] in
            guard let self, let engine, activePlan?.id == plan.id else { return }
            DebugLogger.log(
                "Crossfade watchdog fired: url=\(engine.currentURL?.lastPathComponent ?? "none"), time=\(engine.currentTime), playing=\(engine.isPlaying), scheduled=\(engine.hasScheduledMedia)",
                category: .playback
            )
            if !engine.finishPreparedCrossfade(to: plan.nextFileURL, reason: "watchdog") { onFailure() }
        }
    }

    private func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard delay.isFinite else { return nil }
        return Task {
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
                try Task.checkCancellation()
                fire()
            } catch {
                return
            }
        }
    }

    func reset() {
        deadline?.cancel()
        deadline = nil
        watchdog?.cancel()
        watchdog = nil
        activePlan = nil
    }

    static func target(
        in queue: PlaybackQueueState,
        after song: Song?,
        repeatMode: RepeatMode,
        endsWithCurrentSong: Bool,
        aiEffectActive: Bool
    ) -> PlaybackQueueState.Entry? {
        // AI quick cuts retain their existing eligibility and run with Repeat off.
        guard !endsWithCurrentSong, !aiEffectActive || repeatMode == .off else { return nil }
        return queue.crossfadeEntry(after: song, repeatMode: repeatMode)
    }

    static func shouldInvalidate(
        previousTarget: UUID?,
        nextTarget: UUID?,
        activeTarget: UUID?,
        removed: Set<UUID> = [],
        hasStarted: Bool
    ) -> Bool {
        if let activeTarget, removed.contains(activeTarget) { return true }
        return !hasStarted && previousTarget != nextTarget
    }

    func promoteAtNaturalEnd(
        plan: Plan,
        currentTarget: UUID?,
        in engine: AVEnginePlayback
    ) -> Bool {
        guard engine.hasAudibleCrossfade || plan.target.id == currentTarget else {
            DebugLogger.log("Natural-end crossfade refused: queue target changed", category: .playback)
            return false
        }
        activePlan = plan
        return engine.finishPreparedCrossfade(to: plan.nextFileURL, reason: "natural end")
    }

    /// Invalidates both callbacks before recovery so a queued timer cannot advance again.
    func recover(engine: AVEnginePlayback, didSwapDecks: Bool = false) -> Bool {
        reset()
        let advance = didSwapDecks || !engine.hasPlayableMainMedia
        engine.cancelCrossfade()
        return advance
    }
}
