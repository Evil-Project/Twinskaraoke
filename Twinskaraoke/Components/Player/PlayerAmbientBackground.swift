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
    @State private var animationPhase: Bool = false
    @State private var paletteLoadOwnership = LatestLoadOwnershipGate()

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
        .onChange(of: artworkURL) { loadPalette() }
        .onChange(of: isPlaying) { _, playing in
            if playing { startBreathing() }
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
        .onDisappear {
            paletteLoadOwnership.cancel()
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
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 58)
                        .saturation(1.05)
                        .scaleEffect(shouldAnimateAmbient ? 1.28 : 1.22)
                        .offset(
                            x: shouldAnimateAmbient ? 8 : -8,
                            y: shouldAnimateAmbient ? -6 : 6
                        )
                        .clipped()
                        .drawingGroup()
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
                startPoint: shouldAnimateAmbient ? .topLeading : .top,
                endPoint: shouldAnimateAmbient ? .bottomTrailing : .bottom
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

    private func loadPalette() {
        paletteLoadOwnership.cancel()
        guard let url = artworkURL else {
            palette = .placeholder
            return
        }
        let loadToken = paletteLoadOwnership.begin()
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
                        guard artworkURL == url,
                              paletteLoadOwnership.finish(loadToken)
                        else { return }
                        palette = extracted
                    }
                }
            }
        #endif
    }
}
