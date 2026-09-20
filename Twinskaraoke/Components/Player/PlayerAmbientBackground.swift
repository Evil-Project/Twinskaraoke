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
    @Environment(\.appAnimationsActive) private var animationsActive
    private let scrollState = ScrollPerformanceState.shared
    @State private var palette: ArtworkPalette = .placeholder
    @State private var paletteSourceURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationClock = ActiveAnimationClock()
    @State private var isVisible = false

    private var shouldAnimateAmbient: Bool {
        isPlaying && isVisible && !reduceEffects && scenePhase == .active
    }
    private static let breathingPeriod: TimeInterval = 12
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
        .transaction { $0.animation = nil }
        .onAppear {
            isVisible = true
            loadPalette()
        }
        .onDisappear {
            isVisible = false
            animationClock.setRunning(false, at: .now)
        }
        .onChange(of: artworkURL) { loadPalette() }
        .onChange(of: shouldAnimateAmbient, initial: true) { _, running in
            animationClock.setRunning(running, at: .now)
        }
    }
    private static func breathingPhase(elapsed: TimeInterval) -> Double {
        let cycle = elapsed
            .truncatingRemainder(dividingBy: breathingPeriod) / breathingPeriod
        return (1 - cos(2 * .pi * cycle)) / 2
    }

    @ViewBuilder
    private var blurredArtworkLayer: some View {
        if let artworkURL {
            let backdropURL = ArtworkURLBuilder.variantURL(from: artworkURL, variant: .blur) ?? artworkURL
            Color.clear
                .overlay {
                    WebImage(
                        url: backdropURL,
                        options: ImageCacheConfig.defaultOptions,
                        context: ImageCacheConfig.visibleImageContext
                    ) { image in
                        TimelineView(
                            .animation(
                                minimumInterval: DisplayRefreshRate.ambientAnimationInterval,
                                paused: !shouldAnimateAmbient
                            )
                        ) { context in
                            let phase = Self.breathingPhase(
                                elapsed: animationClock.elapsed(at: context.date)
                            )
                            image
                                .resizable()
                                .interpolation(.low)
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: runtimeBlurRadius)
                                .saturation(1.05)
                                .drawingGroup(opaque: true, colorMode: .linear)
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
        paletteSourceURL = url
        #if canImport(UIKit)
            SDWebImageManager.shared.loadImage(
                with: url,
                options: [],
                context: ImageCacheConfig.visibleImageContext,
                progress: nil
            ) { image, _, _, _, _, _ in
                guard let image else { return }
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
