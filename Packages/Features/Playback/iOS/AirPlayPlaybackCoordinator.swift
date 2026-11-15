@MainActor
enum AirPlayPlaybackCoordinator {
    static func cancelTransition(in manager: AudioPlayerManager) {
        manager.airPlaySamples?.cancelTransition(url: manager.currentPlaybackURL)
    }

    static func prepareTransition(_ plan: TransitionCoordinator.TransitionPlan, in manager: AudioPlayerManager) -> Bool {
        if let samples = manager.airPlaySamples, let url = manager.currentPlaybackURL {
            samples.prepareTransition(from: url, plan: plan) { [weak manager, weak samples] in
                guard let manager, let samples, manager.airPlaySamples === samples else { return false }
                return manager.transitionCoordinator.pendingPlan?.id == plan.id && manager.crossfadeTarget?.id == plan.target.id
            }
            return true
        }
        return false
    }

    static func pollSamples(in manager: AudioPlayerManager) -> Bool {
        guard let samples = manager.airPlaySamples else { return false }
        manager.pollTransition(at: samples.position, duration: manager.playbackDuration)
        return true
    }

    static func pauseSamples(in manager: AudioPlayerManager) -> Bool {
        if let samples = manager.airPlaySamples {
            manager.lastKnownPlaybackTime = samples.position
            manager.streamPlaybackRequested = false
            samples.pause()
            manager.cancelPendingTransitionWork()
            manager.setPlaybackState(playing: false, buffering: false, reason: "pause.airPlaySamples")
            return true
        }
        return false
    }

    static func resumeSamples(in manager: AudioPlayerManager) -> Bool {
        if let samples = manager.airPlaySamples, let url = manager.currentPlaybackURL {
            if !manager.streamPlaybackRequested {
                manager.streamPlaybackRequested = true
                manager.setPlaybackState(playing: false, buffering: true, reason: "resume.airPlaySamples")
                samples.resume(url: url)
            }
            return true
        }
        return false
    }

    static func seekSamples(to fraction: Double, in manager: AudioPlayerManager) -> Bool {
        if let samples = manager.airPlaySamples, let url = manager.currentPlaybackURL, manager.playbackDuration > 0 {
            manager.cancelPendingTransitionWork()
            samples.loadSong(url, at: min(fraction * manager.playbackDuration, max(0, manager.playbackDuration - 0.1)), autoplay: manager.streamPlaybackRequested)
            return true
        }
        return false
    }

    static func canApplyEffects(in manager: AudioPlayerManager) -> Bool {
        canApplyEffects(
            usesAirPlayPlayer: manager.usesAirPlaySongPlayer,
            handoffPending: manager.airPlayHandoffs.isPending,
            loadingLocalEngine: manager.loadedEngine?.isLoadingAirPlayHandoff == true
        )
    }

    static func canApplyEffects(usesAirPlayPlayer: Bool, handoffPending: Bool, loadingLocalEngine: Bool) -> Bool {
        !usesAirPlayPlayer && !handoffPending && !loadingLocalEngine
    }
}
