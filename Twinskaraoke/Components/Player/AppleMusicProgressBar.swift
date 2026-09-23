import SwiftUI

/// Native playback scrubbing, with a continuous track and no thumb or ticks.
struct AppleMusicProgressBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onSeekEnd: (Double) -> Void
    var accessibilityLabel: String = String(localized: "Progress")
    var accessibilityValueText: String?
    var accessibilityHint: String = String(localized: "Swipe up or down to adjust.")
    var scrubValueText: String?
    @State private var scrubHaptics = ScrubHapticFeedback()
    #if DEBUG
    @State private var lastScrubbedValue: Double = 0
    #endif

    var body: some View {
        Slider(
            value: Binding(
                get: { min(1, max(0, progress)) },
                set: { value in
                    #if DEBUG
                    lastScrubbedValue = value
                    #endif
                    scrubHaptics.update(value)?.play()
                    progress = value
                    // Accessibility adjustments do not begin a drag session.
                    if !isScrubbing {
                        AppHaptic.detent.play()
                        onSeekEnd(value)
                    }
                }
            ),
            in: 0...1,
            onEditingChanged: { editing in
                if editing {
                    AppHaptic.detent.prepare()
                    scrubHaptics.begin()?.play()
                } else {
                    scrubHaptics.end()?.play()
                    onSeekEnd(progress)
                }
                isScrubbing = editing
            }
        )
        .onDisappear { _ = scrubHaptics.end(cancelled: true) }
        .sliderThumbVisibility(.hidden)
        .tint(.primary)
        .frame(minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText ?? String(localized: "\(Int(progress * 100)) percent"))
        .accessibilityHint(accessibilityHint)
        .background {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestScrubTracking") {
                NativeScrubValueProbe(value: lastScrubbedValue)
            }
            #endif
        }
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
    var hapticStep: Double?
    var onSet: (Double) -> Void = { _ in }
    @State private var lastFeedbackStep: Int?
    @State private var dragValue: Double?
    @State private var isEditing = false
    @State private var lastCommitUptime: TimeInterval = 0

    var body: some View {
        Slider(
            value: Binding(
                get: { min(range.upperBound, max(range.lowerBound, dragValue ?? value)) },
                set: { newValue in
                    let next = min(range.upperBound, max(range.lowerBound, newValue))
                    if let hapticStep, hapticStep > 0 {
                        let step = Int((next / hapticStep).rounded())
                        if step != lastFeedbackStep {
                            lastFeedbackStep = step
                            AppHaptic.detent.play()
                        }
                    }
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
                if editing { AppHaptic.detent.prepare() }
                if !editing {
                    lastFeedbackStep = nil
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

/// The original 40-notch scrub texture, independent of rendering or value updates.
/// Idle playback and hardware-volume changes must never produce feedback.
struct ScrubHapticFeedback {
    private var active = false
    private var lastDetentIndex: Int?
    private var didHitEdge = false

    mutating func begin() -> AppHaptic? {
        guard !active else { return nil }
        active = true
        lastDetentIndex = nil
        didHitEdge = false
        return .grab
    }

    mutating func update(_ value: Double) -> AppHaptic? {
        guard active, value.isFinite else { return nil }
        let next = min(1, max(0, value))
        let index = Int(next * 40)
        if next == 0 || next == 1 {
            let feedback: AppHaptic? = didHitEdge ? nil : .boundary
            didHitEdge = true
            lastDetentIndex = index
            return feedback
        }
        didHitEdge = false
        guard index != lastDetentIndex else { return nil }
        let feedback: AppHaptic? = lastDetentIndex == nil ? nil : .detent
        lastDetentIndex = index
        return feedback
    }

    mutating func end(cancelled: Bool = false) -> AppHaptic? {
        guard active else { return nil }
        active = false
        lastDetentIndex = nil
        didHitEdge = false
        return cancelled ? nil : .commit
    }
}
