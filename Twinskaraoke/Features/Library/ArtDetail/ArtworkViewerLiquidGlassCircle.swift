import SwiftUI

struct ArtworkViewerLiquidGlassCircle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let strokeWidth = contrast == .increased ? 1.2 : 0.7

        if reduceTransparency {
            content
                .background(Circle().fill(Color.black.opacity(0.78)))
                .overlay(glassStroke(lineWidth: strokeWidth))
                .clipShape(Circle())
                .contentShape(Circle())
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay(glassStroke(lineWidth: strokeWidth))
                .overlay(specularHighlight)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .contentShape(Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(glassStroke(lineWidth: strokeWidth))
                .overlay(specularHighlight)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .clipShape(Circle())
                .contentShape(Circle())
        }
    }

    private func glassStroke(lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(contrast == .increased ? 0.86 : 0.62),
                        .white.opacity(0.18),
                        .black.opacity(0.24),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
    }

    private var specularHighlight: some View {
        Circle()
            .trim(from: 0.04, to: 0.34)
            .stroke(
                .white.opacity(contrast == .increased ? 0.72 : 0.46),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .rotationEffect(.degrees(-18))
            .padding(6)
            .blendMode(.screen)
    }
}
