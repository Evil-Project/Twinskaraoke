import SwiftUI

#if canImport(UIKit)
    import SDWebImage
    import SDWebImageSwiftUI
#endif

struct PlayerAmbientBackground: View {
    let artworkURL: URL?
    var isPlaying: Bool = true
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var palette: ArtworkPalette = .placeholder
    @State private var paletteSourceURL: URL?
    @State private var animationPhase: Bool = false

    private var shouldAnimateAmbient: Bool {
        animationPhase && isPlaying && !reduceMotion
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            blurredArtworkLayer
            colorWashLayer
            vignetteLayer
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: artworkURL)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: palette)
        .onAppear {
            loadPalette()
            if isPlaying { startBreathing() }
        }
        .onDisappear(perform: stopBreathing)
        .onChange(of: artworkURL) { loadPalette() }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startBreathing()
            } else {
                stopBreathing()
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    animationPhase = false
                }
            } else if isPlaying {
                startBreathing()
            }
        }
    }

    private func startBreathing() {
        guard !reduceMotion else {
            animationPhase = false
            return
        }
        withAnimation(
            .easeInOut(duration: 6.0)
                .repeatForever(autoreverses: true)
        ) {
            animationPhase = true
        }
    }

    private func stopBreathing() {
        withAnimation(nil) {
            animationPhase = false
        }
    }

    @ViewBuilder
    private var blurredArtworkLayer: some View {
        if let artworkURL {
            GeometryReader { geo in
                WebImage(
                    url: artworkURL,
                    options: ImageCacheConfig.defaultOptions,
                    context: ImageCacheConfig.visibleImageContext
                ) { image in
                    image
                        .resizable()
                        .interpolation(.low)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: runtimeBlurRadius)
                        .saturation(1.05)
                        .drawingGroup()
                        .scaleEffect(shouldAnimateAmbient ? 1.28 : 1.22)
                        .offset(
                            x: shouldAnimateAmbient ? 8 : -8,
                            y: shouldAnimateAmbient ? -6 : 6
                        )
                        .clipped()
                        .transition(.opacity)
                } placeholder: {
                    fallbackGradient
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
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
        let options = Self.imageTransformOptions(from: artworkURL)
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
