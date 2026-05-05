import SwiftUI

struct LyricsView: View {
  let lyrics: [LyricLine]
  let currentTime: TimeInterval
  let onSeek: (TimeInterval) -> Void
  private var currentIndex: Int {
    guard !lyrics.isEmpty else { return -1 }
    var idx = -1
    for (i, line) in lyrics.enumerated() {
      if currentTime >= line.time { idx = i } else { break }
    }
    return idx
  }
  private var isIntro: Bool {
    guard let first = lyrics.first else { return false }
    return currentTime < first.time
  }
  var body: some View {
    if lyrics.isEmpty {
      VStack(spacing: 14) {
        LyricsBouncingDots(isActive: true, dotSize: 12, color: .primary.opacity(0.6))
        Text("Loading lyrics")
          .font(.system(size: 14))
          .foregroundColor(.primary.opacity(0.6))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 0)
            if let first = lyrics.first {
              IntroDots(isActive: isIntro, startTime: first.time, currentTime: currentTime)
                .id("intro-dots")
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { onSeek(0) }
            }
            ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
              LyricLineRow(
                line: line,
                index: index,
                currentIndex: currentIndex,
                currentTime: currentTime,
                nextLineTime: index + 1 < lyrics.count ? lyrics[index + 1].time : nil,
                onSeek: onSeek
              )
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
        .onChange(of: currentIndex) { idx in
          if idx < 0 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
              proxy.scrollTo("intro-dots", anchor: .center)
            }
          } else if idx < lyrics.count {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
              proxy.scrollTo(lyrics[idx].id, anchor: .center)
            }
          }
        }
      }
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

/// Apple Music–style dots used for lyric loading, intro/interlude, and
/// instrumental gaps. When `progress` is provided (0...1), dots illuminate in
/// sequence as the gap to the next lyric line elapses. When `progress` is nil
/// (e.g. loading state with no known timing), dots fall back to a free-running
/// sequential fade.
struct LyricsBouncingDots: View {
  let isActive: Bool
  var progress: Double? = nil
  var dotSize: CGFloat = 9
  var color: Color = .primary
  @State private var loopPhase: Date = .now
  private let loopCycle: TimeInterval = 1.6
  var body: some View {
    if let progress, isActive {
      HStack(spacing: dotSize * 0.55) {
        ForEach(0..<3, id: \.self) { i in
          Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .opacity(syncedOpacity(for: i, progress: progress))
            .scaleEffect(syncedScale(for: i, progress: progress))
        }
      }
      .animation(.easeOut(duration: 0.18), value: progress)
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
        let t = context.date.timeIntervalSince(loopPhase)
          .truncatingRemainder(dividingBy: loopCycle)
        HStack(spacing: dotSize * 0.55) {
          ForEach(0..<3, id: \.self) { i in
            Circle()
              .fill(color)
              .frame(width: dotSize, height: dotSize)
              .opacity(loopOpacity(for: i, t: t))
          }
        }
      }
    }
  }
  private func syncedOpacity(for i: Int, progress: Double) -> Double {
    let p = max(0, min(1, progress))
    let dotStart = Double(i) / 3.0
    let dotEnd = Double(i + 1) / 3.0
    if p <= dotStart { return 0.25 }
    if p >= dotEnd { return 1.0 }
    let local = (p - dotStart) / (dotEnd - dotStart)
    return 0.25 + 0.75 * local
  }
  private func syncedScale(for i: Int, progress: Double) -> CGFloat {
    let p = max(0, min(1, progress))
    let dotStart = Double(i) / 3.0
    let dotEnd = Double(i + 1) / 3.0
    if p <= dotStart { return 1.0 }
    if p >= dotEnd { return 1.18 }
    let local = (p - dotStart) / (dotEnd - dotStart)
    return 1.0 + 0.18 * CGFloat(local)
  }
  private func loopOpacity(for i: Int, t: TimeInterval) -> Double {
    guard isActive else { return 0.35 }
    let perDot = loopCycle / 4.0
    let start = Double(i) * perDot
    let end = start + perDot
    if t < start { return 0.25 }
    if t < end {
      let local = (t - start) / perDot
      return 0.25 + 0.75 * local
    }
    return 1.0
  }
}

private struct LyricLineRow: View {
  let line: LyricLine
  let index: Int
  let currentIndex: Int
  let currentTime: TimeInterval
  let nextLineTime: TimeInterval?
  let onSeek: (TimeInterval) -> Void
  private var isCurrent: Bool { index == currentIndex }
  private var isPast: Bool { index < currentIndex }
  private var distance: Int { abs(index - currentIndex) }
  private var gapProgress: Double? {
    guard let nextLineTime, nextLineTime > line.time else { return nil }
    let elapsed = currentTime - line.time
    let total = nextLineTime - line.time
    return max(0, min(1, elapsed / total))
  }
  private var isInstrumental: Bool {
    let normalized = line.text.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
    return normalized.contains("(instrumental)")
      || normalized.contains("[instrumental]")
      || normalized.contains("♪")
      || normalized == "instrumental"
      || normalized == "..."
      || normalized == "…"
      || normalized.isEmpty
  }
  var body: some View {
    Button {
      onSeek(line.time)
    } label: {
      Group {
        if isInstrumental {
          InstrumentalDots(
            isActive: isCurrent,
            isPast: isPast,
            distance: distance,
            gapProgress: gapProgress
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, isCurrent ? 10 : 6)
        } else {
          Text(line.text)
            .font(.system(size: isCurrent ? 30 : 23, weight: isCurrent ? .bold : .semibold))
            .foregroundColor(lineColor)
            .blur(radius: lineBlur)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, isCurrent ? 10 : 6)
        }
      }
      .padding(.horizontal, 4)
    }
    .buttonStyle(.plain)
    .scaleEffect(isCurrent ? 1.0 : 0.92, anchor: .leading)
    .opacity(isInstrumental ? lineOpacity : lineOpacity)
    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: currentIndex)
  }
  private var lineColor: Color {
    if isCurrent { return .primary }
    if isPast { return .primary.opacity(0.35) }
    return .primary.opacity(0.55)
  }
  private var lineBlur: CGFloat {
    guard isPast else { return 0 }
    return min(CGFloat(distance) * 0.3, 1.2)
  }
  private var lineOpacity: Double {
    if isCurrent { return 1.0 }
    if distance <= 2 { return 1.0 }
    return max(0.5, 1.0 - Double(distance - 2) * 0.1)
  }
}

private struct IntroDots: View {
  let isActive: Bool
  let startTime: TimeInterval
  let currentTime: TimeInterval
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
    .animation(.easeInOut(duration: 0.4), value: isActive)
  }
}
