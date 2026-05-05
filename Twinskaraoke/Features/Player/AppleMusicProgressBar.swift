import SwiftUI

/// Apple Music–style scrubbable progress capsule. Tap-and-drag to seek; the
/// track height grows while the user is scrubbing for stronger feedback.
struct AppleMusicProgressBar: View {
  @Binding var progress: Double
  @Binding var isScrubbing: Bool
  let onSeekEnd: (Double) -> Void
  var trackColor: Color = Color.primary.opacity(0.22)
  var fillColor: Color = .primary
  var idleHeight: CGFloat = 7
  var activeHeight: CGFloat = 12
  var body: some View {
    GeometryReader { geo in
      let height: CGFloat = isScrubbing ? activeHeight : idleHeight
      ZStack(alignment: .leading) {
        Capsule().fill(trackColor)
        Capsule()
          .fill(fillColor)
          .frame(width: max(0, geo.size.width * CGFloat(min(max(progress, 0), 1))))
      }
      .frame(height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if !isScrubbing { isScrubbing = true }
            progress = max(0, min(1, value.location.x / geo.size.width))
          }
          .onEnded { _ in
            onSeekEnd(progress)
            isScrubbing = false
          }
      )
      .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isScrubbing)
    }
    .frame(height: 24)
  }
}
