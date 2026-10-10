import Testing
@testable import Twinskaraoke

@Suite("Transition coordinator")
struct TransitionCoordinatorTests {
    @Test("Auto Mix uses a beat-aligned equal-power fade for close tempos")
    func autoMixFadeForCloseTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 124)

        #expect(result.duration == 8.0)
        #expect(isEqualPower(result.style))
    }

    @Test("Auto Mix uses a short linear cut for incompatible tempos")
    func autoMixFadeForDistantTempos() {
        let result = TransitionCoordinator.computeFade(outBPM: 120, inBPM: 87)

        #expect(result.duration == 1.5)
        #expect(isLinear(result.style))
    }

    @Test("Auto Mix falls back to a music-style crossfade when BPM is unavailable")
    func autoMixFadeWithoutBPM() {
        let result = TransitionCoordinator.computeFade(outBPM: nil, inBPM: 120)

        #expect(result.duration == 6.0)
        #expect(isEqualPower(result.style))
    }

    @Test("Auto Mix rejects invalid cached tempos")
    func autoMixFadeWithInvalidBPM() {
        let zero = TransitionCoordinator.computeFade(outBPM: 0, inBPM: 120)
        let nonFinite = TransitionCoordinator.computeFade(outBPM: .infinity, inBPM: 120)

        #expect(zero.duration == 6.0)
        #expect(isEqualPower(zero.style))
        #expect(nonFinite.duration == 6.0)
        #expect(isEqualPower(nonFinite.style))
    }

    @Test("Harmonic BPM comparison treats double-time tempos as compatible")
    func harmonicBPMDifferenceUsesDoubleTime() {
        #expect(TransitionCoordinator.harmonicBPMDifference(90, 180) == 0)
        #expect(TransitionCoordinator.harmonicBPMDifference(120, 62) == 4)
    }

    /// Repeat Once replays the queue from the top once it ends, so the songs
    /// inside the queue still blend into each other; only the wrap back to
    /// the first song is a plain cut, made by the queue's own advance.
    @MainActor
    @Test("Repeat Once prepares a transition inside the queue but not across its end")
    func repeatOnceTransitionsWithinQueue() {
        let coordinator = TransitionCoordinator()
        var upcoming: [String] = []
        coordinator.onUpcomingSongDetermined = { song in
            if let song { upcoming.append(song.id) }
        }
        let songs = (0..<3).map { index in
            Song(
                id: "repeat-once-\(index)",
                title: "Song \(index)",
                duration: 180,
                absolutePath: nil,
                cloudflareID: nil,
                coverArt: nil,
                originalArtists: ["Artist"],
                coverArtists: nil,
                userUploaded: false
            )
        }
        func poll(_ current: Song) {
            coordinator.poll(
                currentTime: 170,
                totalDuration: 180,
                currentSong: current,
                queue: songs,
                repeatMode: .one,
                autoMixEnabled: false,
                crossfadeEnabled: true,
                crossfadeSeconds: 6,
                aiEffectActive: false
            )
        }

        poll(songs[0])
        #expect(upcoming == [songs[1].id])
        coordinator.reset()

        poll(songs[2])
        #expect(upcoming == [songs[1].id])
        coordinator.reset()
    }

    private func isEqualPower(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .equalPower = style { return true }
        return false
    }

    private func isLinear(_ style: AVEnginePlayback.RampStyle) -> Bool {
        if case .linear = style { return true }
        return false
    }
}
