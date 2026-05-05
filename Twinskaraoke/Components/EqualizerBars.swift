import SwiftUI

struct EqualizerBars: View {
  let isAnimating: Bool
  @State private var startDate = Date()
  @State private var isVisible: Bool = false
  var body: some View {
    GeometryReader { geo in
      let barWidth = geo.size.width / 5
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(isAnimating && isVisible))) {
        context in
        let elapsed = context.date.timeIntervalSince(startDate)
        HStack(alignment: .bottom, spacing: barWidth / 2) {
          ForEach(0..<3) { i in
            Capsule()
              .fill(Color.appAccent)
              .frame(
                width: barWidth,
                height: barHeight(for: i, total: geo.size.height, elapsed: elapsed)
              )
              .animation(.linear(duration: 1.0 / 30), value: elapsed)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
    .onChange(of: isAnimating) { new in
      if new { startDate = Date() }
    }
  }
  private func barHeight(for index: Int, total: CGFloat, elapsed: TimeInterval) -> CGFloat {
    guard isAnimating else { return total * 0.3 }
    let speeds: [Double] = [3.4, 2.7, 4.1]
    let offsets: [Double] = [0.0, 0.45, 0.9]
    let v = (sin(elapsed * speeds[index] + offsets[index] * .pi * 2) + 1) / 2
    return total * (0.3 + 0.7 * v)
  }
}
