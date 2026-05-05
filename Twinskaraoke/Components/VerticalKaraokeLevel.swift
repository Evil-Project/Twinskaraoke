import SwiftUI

/// Vertical fill bar reminiscent of the Apple Music "Sing" vocal-level control:
/// drag anywhere on the track to set the value. Empty when value is 0, fills
/// from the bottom up.
struct VerticalKaraokeLevel: View {
  @Binding var value: Double  // 0...1
  var enabled: Bool = true
  var onSet: (Double) -> Void = { _ in }
  var body: some View {
    GeometryReader { geo in
      let h = geo.size.height
      let clamped = max(0, min(1, value))
      ZStack(alignment: .bottom) {
        Capsule()
          .fill(Color.primary.opacity(enabled ? 0.22 : 0.12))
        Capsule()
          .fill(Color.primary.opacity(enabled ? 1.0 : 0.4))
          .frame(height: max(4, h * CGFloat(clamped)))
          .animation(.spring(response: 0.32, dampingFraction: 0.85), value: value)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            let raw = 1 - (v.location.y / h)
            let next = Double(max(0, min(1, raw)))
            value = next
            onSet(next)
          }
      )
    }
  }
}
