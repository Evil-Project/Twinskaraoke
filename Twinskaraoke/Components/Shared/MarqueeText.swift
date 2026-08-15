import SwiftUI

/// A single line of text that scrolls itself when it is wider than the space it
/// has, then wraps around after a pause.
///
/// The offset is a pure function of elapsed time, sampled by a `TimelineView`,
/// rather than an implicit animation stepped by a `Task`. That is a deliberate
/// correction, and the reason is worth keeping: the previous version drove
/// `phase` with `withAnimation(.linear(duration:))` and then slept for exactly
/// that duration before resetting, which assumed the wall clock and the
/// animation stayed in step. Opening or dismissing the full-screen player runs
/// a `withAnimation` transaction across the whole player subtree
/// (`NowPlayingOverlay`), and a re-render inside somebody else's transaction can
/// drop or re-target an animation already in flight. The sleep kept counting
/// regardless, so `phase` snapped back at a moment unrelated to where the text
/// actually was — the text appeared to stall, jump, and sometimes carry on.
///
/// Sampling time has no such failure mode: whatever happens during a transition,
/// the next frame recomputes the offset the elapsed time says it should have.
/// It is also how the rest of the app animates continuously — see
/// `EqualizerBars` and `PlayerAmbientBackground`.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 35
    var gap: CGFloat = 48
    var startDelay: Double = 1.2

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    /// Whether this view is in the render tree at all, so an off-screen marquee
    /// does not keep a display link alive.
    ///
    /// The `onAppear` half is load-bearing, and its absence was the other half
    /// of the stall. The old version cancelled its animation task in
    /// `onDisappear` and had nothing to restart it: the only paths back in were
    /// a change of text or of measured width. The full-screen player comes back
    /// with the same song at the same size, so neither fired and the marquee
    /// stayed dead until the track changed.
    @State private var isVisible = false

    /// When the current cycle began. Reset rather than accumulated, so the
    /// dwell always lands at the start of a pass.
    @State private var startDate = Date()

    private var needsScroll: Bool {
        !reduceMotion && containerWidth > 0 && textSize.width > containerWidth + 0.5
    }

    private var isScrolling: Bool {
        needsScroll && isVisible
    }

    /// One text plus one gap: the point at which the trailing copy sits exactly
    /// where the leading one started, so wrapping back to zero is invisible.
    private var travel: CGFloat {
        textSize.width + gap
    }

    private var scrollDuration: TimeInterval {
        Double(travel) / Double(max(1, speed))
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                TimelineView(
                    .animation(
                        minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                        paused: !isScrolling
                    )
                ) { context in
                    ZStack(alignment: .leading) {
                        if needsScroll {
                            HStack(spacing: gap) {
                                Text(text).font(font).foregroundStyle(color).fixedSize()
                                Text(text).font(font).foregroundStyle(color).fixedSize()
                            }
                            .offset(x: -phase(at: context.date))
                        } else {
                            Text(text).font(font).foregroundStyle(color).fixedSize()
                        }
                    }
                    // The invisible base Text below is the accessibility
                    // element; these overlay copies are visual-only.
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: needsScroll
                                ? [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.04),
                                    .init(color: .black, location: 0.96),
                                    .init(color: .clear, location: 1),
                                ]
                                : [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 1),
                                ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                guard abs(containerWidth - newWidth) > 0.5 else { return }
                containerWidth = newWidth
                restartCycle()
            }
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    // Measuring copy only; keep it out of the accessibility tree.
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        guard abs(textSize.width - size.width) > 0.5 else { return }
                        textSize = size
                        restartCycle()
                    }
            )
            .onChange(of: text) {
                restartCycle()
            }
            .onAppear {
                isVisible = true
                restartCycle()
            }
            .onDisappear {
                isVisible = false
            }
    }

    private func phase(at date: Date) -> CGFloat {
        Self.phase(
            elapsed: date.timeIntervalSince(startDate),
            travel: travel,
            scrollDuration: scrollDuration,
            startDelay: startDelay
        )
    }

    private func restartCycle() {
        startDate = Date()
    }

    /// How far the text has scrolled `elapsed` seconds into a run.
    ///
    /// Each cycle is a dwell of `startDelay` followed by a linear pass of
    /// `scrollDuration`, and cycles repeat by taking the elapsed time modulo the
    /// two. Being total over every input is the point — there is no state to
    /// fall out of step with, so a pass interrupted by a player transition
    /// resumes at the position the clock says it reached.
    nonisolated static func phase(
        elapsed: TimeInterval,
        travel: CGFloat,
        scrollDuration: TimeInterval,
        startDelay: TimeInterval
    ) -> CGFloat {
        guard travel > 0, scrollDuration > 0 else { return 0 }
        let dwell = max(0, startDelay)
        let cycle = dwell + scrollDuration
        // Clamped rather than mirrored: `startDate` is only ever set to now, so
        // a negative elapsed means the clock moved under us, and starting the
        // cycle over is the sane reading of that.
        let position = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        guard position > dwell else { return 0 }
        return travel * CGFloat((position - dwell) / scrollDuration)
    }
}
