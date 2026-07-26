import SwiftUI

struct VerticalKaraokeLevel: View {
    @Binding var value: Double
    var enabled: Bool = true
    var onSet: (Double) -> Void = { _ in }
    @Environment(\.appReduceMotion) private var reduceMotion
    // In-drag value is local so per-frame drag updates don't publish through
    // the bound model; commits are throttled to ~10Hz for live audio feedback
    // and finalized on drag end.
    @State private var dragValue: Double?
    @State private var lastCommitUptime: TimeInterval = 0

    private var displayValue: Double {
        max(0, min(1, dragValue ?? value))
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let clamped = displayValue
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(enabled ? 0.22 : 0.12))
                Capsule()
                    .fill(Color.primary.opacity(enabled ? 1.0 : 0.4))
                    .frame(height: max(4, h * CGFloat(clamped)))
                    .animation(levelAnimation, value: clamped)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let raw = 1 - (v.location.y / h)
                        let next = Double(max(0, min(1, raw)))
                        dragValue = next
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastCommitUptime >= 0.1 {
                            lastCommitUptime = now
                            value = next
                            onSet(next)
                        }
                    }
                    .onEnded { _ in
                        if let final = dragValue {
                            value = final
                            onSet(final)
                        }
                        dragValue = nil
                        lastCommitUptime = 0
                    }
            )
        }
    }

    private var levelAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }
}
