import Foundation

enum LyricsTranslationControlPresentation {
    static func isDisabled(
        state: LyricsTranslationState,
        isLoading: Bool,
        didFail: Bool,
        hasNoLyrics: Bool,
        hasLyrics: Bool
    ) -> Bool {
        guard !isLoading, !didFail, !hasNoLyrics, hasLyrics else { return true }
        switch state {
        case .translating, .unavailable:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    static func accessibilityLabel(
        showingTranslatedLyrics: Bool,
        hasTranslatedLyrics: Bool,
        state: LyricsTranslationState
    ) -> String {
        if showingTranslatedLyrics { return "Hide Translated Lyrics" }
        if hasTranslatedLyrics { return "Show Translated Lyrics" }
        if state == .failed { return "Retry Lyrics Translation" }
        return "Translate Lyrics"
    }

    static func accessibilityHint(
        state: LyricsTranslationState,
        didFail: Bool,
        hasNoLyrics: Bool,
        hasTranslatedLyrics: Bool
    ) -> String {
        if didFail { return "Reload lyrics before requesting a translation." }
        if hasNoLyrics { return "Lyrics are not available for this song." }
        if hasTranslatedLyrics { return "Toggles translated lyrics." }
        if state == .failed { return "Retries the lyrics translation." }
        if state == .unavailable { return "Lyrics translation is unavailable." }
        return "Requests translated lyrics."
    }
}
