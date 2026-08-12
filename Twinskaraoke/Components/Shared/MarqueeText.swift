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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                guard abs(containerWidth - newWidth) > 0.5 else { return }
                containerWidth = newWidth
                restartAnimation()
            }
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    // Measuring copy only; keep it out of the accessibility tree.
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        guard abs(textSize.width - size.width) > 0.5 else { return }
                        textSize = size
                        restartAnimation()
                    }
            )
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
            try? await Task.sleep(for: .seconds(startDelay))
            while !Task.isCancelled {
                withOptionalAnimation(AppMotion.linear(duration: duration)) {
                    phase = distance
                }
                try? await Task.sleep(for: .seconds(duration))
                if Task.isCancelled { break }
                phase = 0
                try? await Task.sleep(for: .seconds(startDelay))
            }
        }
    }
}
