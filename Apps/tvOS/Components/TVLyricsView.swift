import SwiftUI
struct TVLyricsView: View {
    let lyrics: [LyricLine]
    let currentTime: TimeInterval
    var isLoading: Bool = false
    var didFail: Bool = false
    var hasNoLyrics: Bool = false
    var onRetry: (() -> Void)?

    @Environment(\.appReduceMotion) private var reduceMotion
    private var currentIndex: Int {
        guard !lyrics.isEmpty else { return -1 }
        var low = 0
        var high = lyrics.count - 1
        var result = -1
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= currentTime {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let first = lyrics.first {
                            TVIntroDots(
                                isActive: isIntro,
                                startTime: first.time,
                                currentTime: currentTime
                            )
                            .id(Self.introID)
                            .padding(.vertical, 10)
                        }

                        ForEach(lyrics.indices, id: \.self) { index in
                            TVLyricLineRow(
                                line: lyrics[index],
                                index: index,
                                currentIndex: currentIndex,
                                currentTime: lyrics[index].isInstrumental && index == currentIndex
                                    ? currentTime
                                    : nil,
                                nextLineTime: index + 1 < lyrics.count ? lyrics[index + 1].time : nil
                            )
                            .equatable()
                            .id(lyrics[index].id)
                        }
                        Spacer().frame(height: 260)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 90)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 140)
                    }
                )
                .onChange(of: currentIndex) { _, index in
                    scroll(to: index, proxy: proxy)
                }
                .onAppear {
                    proxy.scrollTo(anchorID(for: currentIndex), anchor: .center)
                }
            }
        }
    }

    private static let introID = "tv-lyrics-intro"

    private func anchorID(for index: Int) -> AnyHashable {
        guard index >= 0, index < lyrics.count else { return AnyHashable(Self.introID) }
        return AnyHashable(lyrics[index].id)
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        let target = anchorID(for: index)
        guard !reduceMotion else {
            proxy.scrollTo(target, anchor: .center)
            return
        }
        withAnimation(AppMotion.gentle) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if didFail {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Couldn't load lyrics")
                    .font(.title3.bold())
                if let onRetry {
                    TVTextButton(title: String(localized: "Retry"), action: onRetry)
                }
            }
        } else if hasNoLyrics {
            VStack(spacing: 16) {
                Image(systemName: "text.quote")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No lyrics for this song")
                    .font(.title3.bold())
                Text("They'll show up here when they're available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if isLoading {
            LyricsBouncingDots(isActive: true, dotSize: 16, color: .primary.opacity(0.6))
                .accessibilityLabel("Loading lyrics")
        }
    }
}

private struct TVLyricLineRow: View, Equatable {
    let line: LyricLine
    let index: Int
    let currentIndex: Int
    let currentTime: TimeInterval?
    let nextLineTime: TimeInterval?

    @Environment(\.appReduceMotion) private var reduceMotion

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line
            && lhs.index == rhs.index
            && lhs.currentIndex == rhs.currentIndex
            && lhs.currentTime == rhs.currentTime
            && lhs.nextLineTime == rhs.nextLineTime
    }

    private var isCurrent: Bool { index == currentIndex }
    private var isPast: Bool { index < currentIndex }
    private var distance: Int { abs(index - currentIndex) }

    private var gapProgress: Double? {
        guard isCurrent,
              let currentTime,
              let nextLineTime,
              nextLineTime > line.time
        else { return nil }
        return max(0, min(1, (currentTime - line.time) / (nextLineTime - line.time)))
    }

    var body: some View {
        Group {
            if line.isInstrumental {
                LyricsBouncingDots(
                    isActive: isCurrent,
                    progress: gapProgress,
                    dotSize: isCurrent ? 18 : 13,
                    color: lineColor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isCurrent ? 14 : 8)
            } else {
                Text(line.text)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(lineColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, isCurrent ? 14 : 8)
            }
        }
        .blur(radius: lineBlur)
        .scaleEffect(reduceMotion ? 1 : (isCurrent ? 1.09 : 0.97), anchor: .leading)
        .opacity(lineOpacity)
        .animation(reduceMotion ? nil : AppMotion.gentle, value: currentIndex)
        .accessibilityLabel(line.isInstrumental ? "Instrumental break" : line.text)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var lineColor: Color {
        if isCurrent { return .primary }
        if isPast { return .primary.opacity(0.32) }
        return .primary.opacity(0.55)
    }

    private var lineBlur: CGFloat {
        guard !reduceMotion, !isCurrent else { return 0 }
        return min(3.0, 1.0 * CGFloat(distance))
    }

    private var lineOpacity: Double {
        if isCurrent { return 1 }
        if distance <= 2 { return 1 }
        return max(0.45, 1 - Double(distance - 2) * 0.12)
    }
}

private struct TVIntroDots: View {
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
            dotSize: 16,
            color: isActive ? .primary : .primary.opacity(0.4)
        )
        .opacity(isActive ? 1 : 0.3)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: isActive)
        .accessibilityLabel("Intro")
    }
}
