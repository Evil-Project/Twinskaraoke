import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 35
    var gap: CGFloat = 48
    var startDelay: Double = 1.2
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var phase: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?
    private var needsScroll: Bool {
        !reduceMotion && containerWidth > 0 && textSize.width > containerWidth + 0.5
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        if needsScroll {
                            HStack(spacing: gap) {
                                Text(text).font(font).foregroundStyle(color).fixedSize()
                                Text(text).font(font).foregroundStyle(color).fixedSize()
                            }
                            .offset(x: -phase)
                        } else {
                            Text(text).font(font).foregroundStyle(color).fixedSize()
                        }
                    }
                    // The invisible base Text below is the accessibility
                    // element; these overlay copies are visual-only.
                    .accessibilityHidden(true)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: needsScroll
                                ? [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.04),
                                    .init(color: .black, location: 0.96),
                                    .init(color: .clear, location: 1),
                                ]
                                : [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 1),
                                ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .onAppear {
                        containerWidth = geo.size.width
                        if animationTask == nil { restartAnimation() }
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        guard abs(containerWidth - newWidth) > 0.5 else { return }
                        containerWidth = newWidth
                        restartAnimation()
                    }
                }
            )
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    // Measuring copy only; keep it out of the accessibility tree.
                    .accessibilityHidden(true)
                    .background(
                        GeometryReader { t in
                            Color.clear.preference(key: TextSizeKey.self, value: t.size)
                        }
                    )
            )
            .onPreferenceChange(TextSizeKey.self) { size in
                if abs(textSize.width - size.width) > 0.5 {
                    textSize = size
                    restartAnimation()
                }
            }
            .onChange(of: text) {
                restartAnimation()
            }
            .onDisappear {
                animationTask?.cancel()
                animationTask = nil
            }
    }

    private func restartAnimation() {
        animationTask?.cancel()
        phase = 0
        guard needsScroll else { return }
        let distance = textSize.width + gap
        let duration = Double(distance) / Double(speed)
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
            while !Task.isCancelled {
                withOptionalAnimation(AppMotion.linear(duration: duration)) {
                    phase = distance
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if Task.isCancelled { break }
                phase = 0
                try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
            }
        }
    }
}

private struct TextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
