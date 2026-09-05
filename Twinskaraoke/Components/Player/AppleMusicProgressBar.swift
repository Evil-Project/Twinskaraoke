import SwiftUI

/// The filled portion of the bar, drawn rather than sized.
///
/// `animatableData` puts the interpolation in the drawing layer: the view's
/// frame never changes, so nothing here participates in the layout animations
/// that carry the full player's movement to its children.
nonisolated private struct ProgressFill: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(0, rect.width * CGFloat(min(max(fraction, 0), 1)))
        guard width > 0 else { return Path() }
        return Capsule().path(
            in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        )
    }
}

struct AppleMusicProgressBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onSeekEnd: (Double) -> Void
    var trackColor: Color = .primary.opacity(0.22)
    var fillColor: Color = .primary
    /// Apple Music's Now Playing bars, and the same for playback position and
    /// volume — they read as one control family rather than two. The volume row
    /// carried these values explicitly while the playback bar kept a thinner
    /// 5/9 default, so the two never matched.
    var idleHeight: CGFloat = 7
    var activeHeight: CGFloat = 12
    var accessibilityLabel: String = "Progress"
    var accessibilityValueText: String?
    var accessibilityHint: String = "Swipe up or down to adjust."
    var scrubValueText: String?
    @ScaledMetric(relativeTo: .body) private var scaledIdleHeight: CGFloat = 7
    @ScaledMetric(relativeTo: .body) private var scaledActiveHeight: CGFloat = 12
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
                    // The fill is drawn, not laid out. `Capsule().frame(width:)`
                    // animates the *frame*, which is the same system SwiftUI
                    // uses to propagate the full player's animated position to
                    // its descendants — so while the player was being dragged or
                    // sprung, the fill's width animation and the player's
                    // movement were interpolating the same geometry at once and
                    // the progress line visibly ran back and forth. Only during
                    // playback, because paused there is no width change to
                    // interact with.
                    //
                    // As a `Shape` with `animatableData`, the frame is constant
                    // and only the path is interpolated. The parent's transform
                    // is applied to the result afterwards, so the two can no
                    // longer interfere — and the fill keeps its own animation
                    // rather than having to hold still while the player moves.
                    ProgressFill(fraction: clampedProgress)
                        .fill(fillColor)
                        .frame(width: width, height: height)
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
