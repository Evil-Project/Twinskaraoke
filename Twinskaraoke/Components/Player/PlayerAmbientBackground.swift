import SwiftUI

#if canImport(UIKit)
    import SDWebImage
    import SDWebImageSwiftUI
#endif

struct PlayerAmbientBackground: View {
    let artworkURL: URL?
    var isPlaying: Bool = true
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appReduceEffects) private var reduceEffects
    @State private var palette: ArtworkPalette = .placeholder
    @State private var paletteSourceURL: URL?
    /// Breath time already run before the current stretch of playback.
    @State private var breathElapsed: TimeInterval = 0
    /// When the current stretch of playback began.
    @State private var breathResumedAt = Date()

    private var shouldAnimateAmbient: Bool {
        isPlaying && !reduceEffects
    }

    /// Seconds for one full out-and-back breath.
    private static let breathingPeriod: TimeInterval = 12

    /// Defence in depth against the backdrop's extent depending on safe-area
    /// insets. `.ignoresSafeArea()` does not pin a view to the screen, it expands
    /// it *by the current insets*, so anything that moves those insets moves this
    /// backdrop's edges with them. Overscanning keeps the painted area past every
    /// edge whatever the insets do; the host clips the overflow.
    ///
    /// Sized against the insets themselves rather than the screen: the largest
    /// this has to clear is one safe-area inset, ~67pt at the extreme on device,
    /// so this leaves comfortable headroom for taller hardware. Scaling it to the
    /// display would overscan an iPad far past anything the insets can reach and
    /// pay for it in blurred area on every frame.
    private static let safeAreaOverscan: CGFloat = 96

    var body: some View {
        ZStack {
            Color(.systemBackground)
            blurredArtworkLayer
            colorWashLayer
            vignetteLayer
        }
        .padding(-Self.safeAreaOverscan)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: artworkURL)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: palette)
        // A `withAnimation` transaction applies to every animatable change in
        // the update, not just the state it wraps, so a `repeatForever` started
        // anywhere in the app could latch onto this backdrop's geometry and
        // oscillate it forever. This is a decorative full-bleed layer that
        // should never inherit motion from elsewhere: drop any ambient
        // animation at the boundary. The `.animation(_:value:)` modifiers above
        // sit inside it and still drive the backdrop's own transitions.
        .transaction { $0.animation = nil }
        .onAppear(perform: loadPalette)
        .onChange(of: artworkURL) { loadPalette() }
        .onChange(of: shouldAnimateAmbient) { _, animating in
            // Bank the time already breathed when stopping, and restart the
            // clock when resuming, so the breath picks up where it left off
            // rather than jumping to wherever wall-clock time has reached.
            if animating {
                breathResumedAt = Date()
            } else {
                breathElapsed += Date().timeIntervalSince(breathResumedAt)
            }
        }
    }

    /// How far the breath has run, in seconds, across every stretch of playback.
    private func breathDuration(at date: Date) -> TimeInterval {
        guard shouldAnimateAmbient else { return breathElapsed }
        return breathElapsed + max(0, date.timeIntervalSince(breathResumedAt))
    }

    /// Progress through the breath, 0...1 and back, eased at the turns.
    ///
    /// Driven off the clock rather than a `repeatForever` animation. An endless
    /// SwiftUI animation is a transaction, and a transaction applies to every
    /// animatable change in its subtree — including the safe-area expansion that
    /// sizes this backdrop. Started that way, the breath latched onto the
    /// backdrop's top edge and oscillated it between the real inset and zero for
    /// as long as the view lived, sliding the artwork off screen and exposing the
    /// layer beneath. Scoping it with `.animation(_:value:)` was not enough:
    /// that modifier still animates everything in its subtree, so keying one on
    /// the play/pause flag would re-arm the same leak on the same trigger. A
    /// clock produces the same motion with no transaction to leak, and `paused:`
    /// stops it without leaving anything running.
    private static func breathingPhase(elapsed: TimeInterval) -> Double {
        let cycle = elapsed
            .truncatingRemainder(dividingBy: breathingPeriod) / breathingPeriod
        return (1 - cos(2 * .pi * cycle)) / 2
    }

    @ViewBuilder
    private var blurredArtworkLayer: some View {
        if let artworkURL {
            // The backdrop is blurred beyond recognition anyway, so load the
            // 32px server-blurred variant instead of the full card image:
            // far less decode, memory and GPU work for the same visual result.
            let backdropURL = ArtworkURLBuilder.variantURL(from: artworkURL, variant: .blur) ?? artworkURL
            // The image goes in an `overlay` so it cannot influence the size of
            // anything above it. `.aspectRatio(.fill)` always resolves to a size
            // that *covers* the proposal, and `.frame(maxWidth:maxHeight:)` does
            // not clamp a child that came back larger — it adopts the child's
            // size. That let the image inflate the frame, the frame inflate the
            // ZStack, and the backdrop end up laid out at the artwork's aspect
            // ratio instead of the screen's, so it no longer covered the display.
            // Overlay content never feeds size back to its parent, which keeps the
            // clamp without an explicit numeric frame for an animation to
            // interpolate.
            Color.clear
                .overlay {
                    WebImage(
                        url: backdropURL,
                        options: ImageCacheConfig.defaultOptions,
                        context: ImageCacheConfig.visibleImageContext
                    ) { image in
                        TimelineView(
                            .animation(
                                minimumInterval: DisplayRefreshRate.decorativeAnimationInterval,
                                paused: !shouldAnimateAmbient
                            )
                        ) { context in
                            let phase = Self.breathingPhase(
                                elapsed: breathDuration(at: context.date)
                            )
                            image
                                .resizable()
                                .interpolation(.low)
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: runtimeBlurRadius)
                                .saturation(1.05)
                                // Deliberately no `.drawingGroup()`. It bought
                                // nothing here — the source is the 32px
                                // server-blurred variant above, so there is no
                                // costly rasterization worth caching — while
                                // forcing a full-screen offscreen pass on every
                                // re-render, and this view re-renders constantly
                                // because `audioManager` republishes during
                                // playback. `.blur` on its own is a hardware
                                // filter and needs no offscreen buffer.
                                .scaleEffect(1.22 + 0.06 * phase)
                                .offset(
                                    x: -8 + 16 * phase,
                                    y: 6 - 12 * phase
                                )
                        }
                        .transition(.opacity)
                    } placeholder: {
                        fallbackGradient
                    }
                }
                .clipped()
        } else {
            fallbackGradient
        }
    }

    private var colorWashLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.primary.opacity(0.36),
                    palette.secondary.opacity(0.22),
                    palette.tertiary.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(Color.appAmbientWash)
        }
    }

    private var vignetteLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.appAmbientVignetteTop,
                    Color.appAmbientVignetteMid,
                    Color.appAmbientVignetteBottom,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.clear,
                    Color.appAmbientRadial,
                ],
                center: .center,
                startRadius: 140,
                endRadius: 520
            )
        }
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [
                palette.primary,
                palette.secondary,
                palette.tertiary,
                palette.quaternary,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var runtimeBlurRadius: CGFloat {
        guard let artworkURL else { return 0 }
        let backdropURL = ArtworkURLBuilder.variantURL(from: artworkURL, variant: .blur) ?? artworkURL
        let options = Self.imageTransformOptions(from: backdropURL)
        let sourceBlur = options["blur"].flatMap(Double.init) ?? 0
        let sourceWidth = options["width"].flatMap(Double.init)
        return sourceBlur > 0 || sourceWidth.map { $0 <= 32 } == true ? 12 : 42
    }

    private static func imageTransformOptions(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var options: [String: String] = [:]
        for item in components.queryItems ?? [] {
            options[item.name.lowercased()] = item.value ?? ""
        }

        let pathParts = components.path.split(separator: "/")
        guard let imageIndex = pathParts.indices.first(where: {
            pathParts[$0] == "image" && $0 > pathParts.startIndex && pathParts[$0 - 1] == "cdn-cgi"
        }) else { return options }

        let optionIndex = pathParts.index(after: imageIndex)
        guard optionIndex < pathParts.endIndex else { return options }
        for option in pathParts[optionIndex].split(separator: ",") {
            let pair = option.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            options[String(pair[0]).lowercased()] = String(pair[1])
        }
        return options
    }

    private func loadPalette() {
        guard let url = artworkURL else {
            paletteSourceURL = nil
            palette = .placeholder
            return
        }
        // Tag the request with its URL so a slow extraction for an older
        // artwork can't overwrite a newer palette after quick song skips.
        paletteSourceURL = url
        #if canImport(UIKit)
            SDWebImageManager.shared.loadImage(
                with: url,
                options: [],
                context: ImageCacheConfig.visibleImageContext,
                progress: nil
            ) { image, _, _, _, _, _ in
                guard let image else { return }
                // Pixel sampling is too heavy for the main-queue completion.
                Task.detached(priority: .utility) {
                    let extracted = ArtworkPalette(image: image)
                    await MainActor.run {
                        guard paletteSourceURL == url else { return }
                        palette = extracted
                    }
                }
            }
        #endif
    }
}
