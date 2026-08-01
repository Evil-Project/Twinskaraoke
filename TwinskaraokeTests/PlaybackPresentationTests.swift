import Testing
@testable import Twinskaraoke

@Suite("Playback presentation")
struct PlaybackPresentationTests {
    @Test("Failed lyrics translation remains retryable")
    func failedLyricsTranslationIsRetryable() {
        let isDisabled = LyricsTranslationControlPresentation.isDisabled(
            state: .failed,
            isLoading: false,
            didFail: false,
            hasNoLyrics: false,
            hasLyrics: true
        )

        #expect(!isDisabled)
        #expect(
            LyricsTranslationControlPresentation.accessibilityLabel(
                showingTranslatedLyrics: false,
                hasTranslatedLyrics: false,
                state: .failed
            ) == "Retry Lyrics Translation"
        )
        #expect(
            LyricsTranslationControlPresentation.accessibilityHint(
                state: .failed,
                didFail: false,
                hasNoLyrics: false,
                hasTranslatedLyrics: false
            ) == "Retries the lyrics translation."
        )
    }

    @Test("Radio status distinguishes ready, buffering, and on-air states")
    func radioLiveStatusMapping() {
        let ready = RadioLiveStatusPresentation(
            isRadioMode: false,
            isPlaying: true,
            isBuffering: true
        )
        let buffering = RadioLiveStatusPresentation(
            isRadioMode: true,
            isPlaying: true,
            isBuffering: true
        )
        let onAir = RadioLiveStatusPresentation(
            isRadioMode: true,
            isPlaying: true,
            isBuffering: false
        )

        #expect(ready == .ready)
        #expect(ready.title == "Live Ready")
        #expect(ready.badgeText == "READY")
        #expect(ready.accessibilityLabel == "Live radio ready")

        #expect(buffering == .buffering)
        #expect(buffering.title == "Connecting")
        #expect(buffering.badgeText == "CONNECTING")
        #expect(buffering.accessibilityLabel == "Live radio connecting")

        #expect(onAir == .onAir)
        #expect(onAir.title == "On Air")
        #expect(onAir.badgeText == "LIVE")
        #expect(onAir.accessibilityLabel == "Live radio on air")
    }
}
