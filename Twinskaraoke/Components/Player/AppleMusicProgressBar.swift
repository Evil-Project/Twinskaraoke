import SwiftUI

/// Native playback scrubbing, with a continuous track and no thumb or ticks.
struct AppleMusicProgressBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onSeekEnd: (Double) -> Void
    var accessibilityLabel: String = "Progress"
    var accessibilityValueText: String?
    var accessibilityHint: String = "Swipe up or down to adjust."
    var scrubValueText: String?

    var body: some View {
        Slider(
            value: Binding(
                get: { min(1, max(0, progress)) },
                set: { value in
                    progress = value
                    // Accessibility adjustments do not begin a drag session.
                    if !isScrubbing { onSeekEnd(value) }
                }
            ),
            in: 0...1,
            onEditingChanged: { editing in
                if !editing { onSeekEnd(progress) }
                isScrubbing = editing
            }
        )
        .sliderThumbVisibility(.hidden)
        .tint(.primary)
        .frame(minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText ?? "\(Int(progress * 100)) percent")
        .accessibilityHint(accessibilityHint)
        .overlay(alignment: .top) {
            if isScrubbing, let scrubValueText {
                Text(scrubValueText)
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .offset(y: -20)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Keeps live audio changes throttled while UIKit/SwiftUI owns interaction.
struct NativeLevelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var neutralValue: Double?
    var onSet: (Double) -> Void = { _ in }
    @State private var dragValue: Double?
    @State private var isEditing = false
    @State private var lastCommitUptime: TimeInterval = 0

    var body: some View {
        Slider(
            value: Binding(
                get: { min(range.upperBound, max(range.lowerBound, dragValue ?? value)) },
                set: { newValue in
                    let next = min(range.upperBound, max(range.lowerBound, newValue))
                    if isEditing {
                        dragValue = next
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastCommitUptime >= 0.1 {
                            commit(next)
                            lastCommitUptime = now
                        }
                    } else {
                        commit(next)
                    }
                }
            ),
            in: range,
            neutralValue: neutralValue,
            label: { EmptyView() },
            onEditingChanged: { editing in
                isEditing = editing
                if !editing {
                    if let dragValue { commit(dragValue) }
                    dragValue = nil
                    lastCommitUptime = 0
                }
            }
        )
        .sliderThumbVisibility(.hidden)
    }

    private func commit(_ next: Double) {
        value = next
        onSet(next)
    }
}
