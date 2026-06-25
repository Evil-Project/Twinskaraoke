import SwiftUI

struct PinchToZoomModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.gesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = max(1, min(5, lastScale * value.magnification))
                }
                .onEnded { _ in
                    finishZoom()
                }
        )
    }

    private func finishZoom() {
        lastScale = scale
        if scale <= 1 {
            if reduceMotion {
                offset = .zero
                lastOffset = .zero
            } else {
                withAnimation(.spring()) {
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
}
