import SwiftUI

struct AppleMusicProgressBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onSeekEnd: (Double) -> Void
    var trackColor: Color = .primary.opacity(0.22)
    var fillColor: Color = .primary
    var idleHeight: CGFloat = 5
    var activeHeight: CGFloat = 9
    var accessibilityLabel: String = "Progress"
    var accessibilityValueText: String?
    var accessibilityHint: String = "Swipe up or down to adjust."
    var scrubValueText: String?
    @ScaledMetric(relativeTo: .body) private var scaledIdleHeight: CGFloat = 5
    @ScaledMetric(relativeTo: .body) private var scaledActiveHeight: CGFloat = 9
    @ScaledMetric(relativeTo: .body) private var scaledIdleThumbDiameter: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var scaledActiveThumbDiameter: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var scaledBubbleWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var scaledBubbleHeight: CGFloat = 22
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var didBeginScrubbing = false
    @State private var lastDetentIndex: Int?
    @State private var didHitEdge = false

    /// Notches across the full bar.  40 puts them ~2.5% apart, which on a
    /// typical song is a few seconds per tick — dense enough to feel like
    /// texture under the thumb, sparse enough that each tick stays distinct.
    private static let detentCount = 40

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var controlHeight: CGFloat {
        scrubValueText == nil
            ? max(24, scaledActiveThumbDiameter + 10)
            : max(42, scaledBubbleHeight + 20)
    }

    var body: some View {
        GeometryReader { geo in
            let height = isScrubbing ? max(activeHeight, scaledActiveHeight) : max(idleHeight, scaledIdleHeight)
            let width = max(geo.size.width, 1)
            let thumbDiameter = isScrubbing ? scaledActiveThumbDiameter : scaledIdleThumbDiameter
            let thumbCenterX = min(
                max(width * CGFloat(clampedProgress), thumbDiameter / 2),
                width - thumbDiameter / 2
            )
            let bubbleWidth = scaledBubbleWidth
            let bubbleCenterX = min(max(thumbCenterX, bubbleWidth / 2), width - bubbleWidth / 2)
            let barCenterY = scrubValueText == nil ? controlHeight / 2 : controlHeight - 11
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(0, width * CGFloat(clampedProgress)))
                    Circle()
                        .fill(fillColor)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(isScrubbing ? 0.22 : 0), radius: 5, x: 0, y: 2)
                        .offset(x: thumbCenterX - thumbDiameter / 2)
                        .opacity(isScrubbing ? 1 : 0)
                        .scaleEffect(reduceMotion ? 1 : (isScrubbing ? 1 : 0.72))
                }
                .frame(width: width, height: height)
                .position(x: width / 2, y: barCenterY)

                if let scrubValueText, isScrubbing {
                    Text(scrubValueText)
                        .font(.caption.monospacedDigit())
                        .bold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: bubbleWidth, height: scaledBubbleHeight)
                        .background(
                            Capsule()
                                .fill(Color.appGlassFillStrong)
                                .shadow(color: Color.appShadow, radius: 8, y: 4)
                        )
                        .position(x: bubbleCenterX, y: 9)
                        .transition(scrubBubbleTransition)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: controlHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                        }
                        if !didBeginScrubbing {
                            didBeginScrubbing = true
                            AppHaptic.detent.prepare()
                            AppHaptic.grab.play()
                        }
                        let next = max(0, min(1, value.location.x / width))
                        playScrubFeedback(at: next)
                        progress = next
                    }
                    .onEnded { _ in
                        let finalProgress = clampedProgress
                        onSeekEnd(finalProgress)
                        isScrubbing = false
                        didBeginScrubbing = false
                        lastDetentIndex = nil
                        didHitEdge = false
                        AppHaptic.commit.play()
                    }
            )
            .animation(scrubAnimation, value: isScrubbing)
            .animation(isScrubbing || reduceMotion ? nil : .linear(duration: 0.25), value: clampedProgress)
        }
        .frame(height: controlHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText ?? "\(Int(clampedProgress * 100)) percent")
        .accessibilityHint(accessibilityHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustProgress(by: 0.05)
            case .decrement:
                adjustProgress(by: -0.05)
            @unknown default:
                break
            }
        }
    }

    /// Ticks once per notch crossed, and thumps once when travel stops against
    /// either end.  The edge flag latches so holding a finger past the end
    /// doesn't repeat the thump every frame.
    private func playScrubFeedback(at next: Double) {
        if next <= 0 || next >= 1 {
            if !didHitEdge {
                didHitEdge = true
                AppHaptic.boundary.play()
            }
            // Seed the notch index even though no detent plays here. Otherwise a
            // drag that starts at an edge — or travels out to one and back —
            // leaves this nil, and the `lastDetentIndex != nil` guard below eats
            // the first interior notch. The guard is meant to fire once per
            // gesture, not once per edge visit.
            lastDetentIndex = Int(next * Double(Self.detentCount))
            return
        }
        didHitEdge = false

        let index = Int(next * Double(Self.detentCount))
        guard index != lastDetentIndex else { return }
        // Skip the very first comparison so picking the thumb up doesn't tick
        // on top of the `.grab` that just played.
        if lastDetentIndex != nil {
            AppHaptic.detent.play()
        }
        lastDetentIndex = index
    }

    private func adjustProgress(by delta: Double) {
        let nextProgress = min(max(progress + delta, 0), 1)
        progress = nextProgress
        onSeekEnd(nextProgress)
        AppHaptic.detent.play()
    }

    private var scrubAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var scrubBubbleTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity)
    }
}
