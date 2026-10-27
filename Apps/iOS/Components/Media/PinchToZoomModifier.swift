import SwiftUI

struct PinchToZoomModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    let reduceMotion: Bool
    /// Pulls a pan offset back inside the bounds that apply at a given
    /// scale. Zooming out from a deep pan otherwise leaves the image wherever
    /// the larger scale had put it, partly or wholly off screen.
    var clampOffset: ((CGSize, CGFloat) -> CGSize)?

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
        if scale > 1, let clampOffset {
            let clamped = clampOffset(offset, scale)
            guard clamped != offset else { return }
            if reduceMotion {
                offset = clamped
                lastOffset = clamped
            } else {
                withAnimation(.spring()) {
                    offset = clamped
                    lastOffset = clamped
                }
            }
        } else if scale <= 1 {
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
