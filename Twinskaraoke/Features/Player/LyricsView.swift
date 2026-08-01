import SwiftUI

struct LyricsView: View {
    let lyrics: [LyricLine]
    let currentTime: TimeInterval
    var showTranslations: Bool = false
    var isLoading: Bool = false
    var didFail: Bool = false
    var hasNoLyrics: Bool = false
    let onSeek: (TimeInterval) -> Void
    var onRetry: (() -> Void)?
    @Environment(\.appReduceMotion) private var reduceMotion

    private var scrollAnimation: Animation? {
        reduceMotion ? nil : AppMotion.gentle
    }

    private var currentIndex: Int {
        guard !lyrics.isEmpty else { return -1 }
        var lo = 0, hi = lyrics.count - 1, result = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lyrics[mid].time <= currentTime { result = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return result
    }

    private var isIntro: Bool {
        guard let first = lyrics.first else { return false }
        return currentTime < first.time
    }

    var body: some View {
        if lyrics.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Spacer().frame(height: 0)
                        if let first = lyrics.first {
                            IntroDots(isActive: isIntro, startTime: first.time, currentTime: currentTime)
                                .id("intro-dots")
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    AppHaptic.selection.play()
                                    onSeek(0)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Intro")
                                .accessibilityValue(introAccessibilityValue(startTime: first.time))
                                .accessibilityHint("Double tap to restart the song.")
                                .accessibilityAddTraits(isIntro ? .isSelected : [])
                                .accessibilityAction {
                                    AppHaptic.selection.play()
                                    onSeek(0)
                                }
                        }
                        ForEach(lyrics.indices, id: \.self) { index in
                            let line = lyrics[index]
                            LyricLineRow(
                                line: line,
                                index: index,
                                currentIndex: currentIndex,
                                currentTime: line.isInstrumental && index == currentIndex
                                    ? currentTime
                                    : nil,
                                showTranslation: showTranslations,
                                nextLineTime: index + 1 < lyrics.count ? lyrics[index + 1].time : nil,
                                onSeek: { time in
                                    scrollTo(line.id, proxy: proxy, animated: false)
                                    onSeek(time)
                                }
                            )
                            .equatable()
                            .id(line.id)
                        }
                        Spacer().frame(height: 120)
                    }
                    .padding(.horizontal, 28)
                }
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 60)
                    }
                )
                .onChange(of: currentIndex) { _, idx in
                    if idx < 0 {
                        scrollTo("intro-dots", proxy: proxy)
                    } else if idx < lyrics.count {
                        scrollTo(lyrics[idx].id, proxy: proxy)
                    }
                }
            }
        }
    }

    private func scrollTo(_ id: some Hashable, proxy: ScrollViewProxy, animated: Bool = true) {
        guard animated, let scrollAnimation else {
            proxy.scrollTo(id, anchor: .center)
            return
        }
        withAnimation(scrollAnimation) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct InstrumentalDots: View {
    let isActive: Bool
    let isPast: Bool
    let distance: Int
    let gapProgress: Double?
    var body: some View {
        LyricsBouncingDots(
            isActive: isActive,
            progress: isActive ? gapProgress : nil,
            dotSize: isActive ? 12 : 9,
            color: dotColor
        )
    }

    private var dotColor: Color {
        if isActive { return .primary }
        if isPast { return .primary.opacity(0.35) }
        return .primary.opacity(0.55)
    }
}

private struct LyricLineRow: View, Equatable {
    let line: LyricLine
    let index: Int
    let currentIndex: Int
    let currentTime: TimeInterval?
    let showTranslation: Bool
    let nextLineTime: TimeInterval?
    let onSeek: (TimeInterval) -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    private var isCurrent: Bool {
        index == currentIndex
    }

    private var isPast: Bool {
        index < currentIndex
    }

    private var distance: Int {
        abs(index - currentIndex)
    }

    private var gapProgress: Double? {
        guard isCurrent,
              let currentTime,
              let nextLineTime,
              nextLineTime > line.time
        else { return nil }
        let elapsed = currentTime - line.time
        let total = nextLineTime - line.time
        return max(0, min(1, elapsed / total))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line
            && lhs.index == rhs.index
            && lhs.currentIndex == rhs.currentIndex
            && lhs.currentTime == rhs.currentTime
            && lhs.showTranslation == rhs.showTranslation
            && lhs.nextLineTime == rhs.nextLineTime
    }

    var body: some View {
        Button {
            onSeek(line.time)
        } label: {
            Group {
                if line.isInstrumental {
                    InstrumentalDots(
                        isActive: isCurrent,
                        isPast: isPast,
                        distance: distance,
                        gapProgress: gapProgress
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, isCurrent ? 10 : 6)
                } else {
                    VStack(alignment: .leading, spacing: isCurrent ? 6 : 3) {
                        Text(line.text)
                            .scaledSystemFont(size: isCurrent ? 30 : 23, weight: isCurrent ? .bold : .semibold)
                            .foregroundStyle(lineColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if showTranslation,
                           let translated = line.translatedText,
                           !translated.isEmpty,
                           translated != line.text
                        {
                            Text(translated)
                                .scaledSystemFont(size: isCurrent ? 18 : 15, weight: .medium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(translationTransition)
                        }
                    }
                    .padding(.vertical, isCurrent ? 10 : 6)
                }
            }
            .padding(.horizontal, 4)
            .blur(radius: lineBlur)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.82, haptic: .selection))
        .scaleEffect(reduceMotion ? 1.0 : (isCurrent ? 1.0 : 0.92), anchor: .leading)
        .opacity(lineOpacity)
        .animation(lineAnimation, value: currentIndex)
        .animation(translationAnimation, value: showTranslation)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double tap to jump to this lyric.")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityAction(named: "Jump to Lyric") {
            AppHaptic.selection.play()
            onSeek(line.time)
        }
    }

    private var accessibilityLabel: String {
        line.isInstrumental ? "Instrumental break" : line.text
    }

    private var accessibilityValue: String {
        var values = [lineStatus, formattedLyricTime(line.time)]
        if showTranslation,
           let translated = line.translatedText,
           !translated.isEmpty,
           translated != line.text
        {
            values.append(translated)
        }
        return values.joined(separator: ", ")
    }

    private var lineStatus: String {
        if isCurrent { return "Current lyric" }
        if isPast { return "Past lyric" }
        return "Upcoming lyric"
    }

    private var lineAnimation: Animation? {
        reduceMotion ? nil : AppMotion.gentle
    }

    private var translationAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var translationTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var lineColor: Color {
        if isCurrent { return .primary }
        if isPast { return .primary.opacity(0.35) }
        return .primary.opacity(0.55)
    }

    private var lineBlur: CGFloat {
        // Depth-of-field: the active line stays crisp while lines soften with
        // distance, like Apple Music. Skipped under reduce motion, where the
        // constant refocusing would read as movement.
        guard !reduceMotion, !isCurrent else { return 0 }
        return min(2.0, 0.7 * CGFloat(distance))
    }

    private var lineOpacity: Double {
        if isCurrent { return 1.0 }
        if distance <= 2 { return 1.0 }
        return max(0.5, 1.0 - Double(distance - 2) * 0.1)
    }

}

private func formattedLyricTime(_ seconds: TimeInterval) -> String {
    let clamped = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", clamped / 60, clamped % 60)
}

private func introAccessibilityValue(startTime: TimeInterval) -> String {
    if startTime <= 1 {
        return "No intro"
    }
    return "First lyric at \(formattedLyricTime(startTime))"
}

private extension LyricsView {
    @ViewBuilder
    var emptyState: some View {
        if didFail {
            VStack(spacing: 14) {
                MusicEmptyState(
                    title: "Couldn't load lyrics",
                    message: "Check your connection and try again."
                )
                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Text("Retry")
                            .scaledSystemFont(size: 14, weight: .semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(.primary.opacity(0.12))
                            )
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
        } else if hasNoLyrics {
            MusicEmptyState(
                title: "No lyrics for this song",
                message: "Lyrics will appear here when they are available."
            )
        } else {
            LyricsLoadingSkeleton()
        }
    }
}

private struct LyricsLoadingSkeleton: View {
    var body: some View {
        LyricsBouncingDots(isActive: true, dotSize: 12, color: .primary.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading lyrics")
    }
}

private struct IntroDots: View {
    let isActive: Bool
    let startTime: TimeInterval
    let currentTime: TimeInterval
    @Environment(\.appReduceMotion) private var reduceMotion
    private var progress: Double {
        guard startTime > 0 else { return 1 }
        return max(0, min(1, currentTime / startTime))
    }

    var body: some View {
        LyricsBouncingDots(
            isActive: isActive,
            progress: isActive ? progress : nil,
            dotSize: 11,
            color: isActive ? .primary : .primary.opacity(0.4)
        )
        .opacity(isActive ? 1.0 : 0.3)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: isActive)
    }

}
