import SwiftUI
import Combine

class CloudProvider: ObservableObject {
    @Published var offset: CGSize
    @Published var frameHeightRatio: CGFloat

    init() {
        frameHeightRatio = CGFloat.random(in: 0.7 ..< 1.4)
        offset = CGSize(
            width: CGFloat.random(in: -150 ..< 150),
            height: CGFloat.random(in: -150 ..< 150)
        )
    }
}

struct Cloud: View {
    @StateObject var provider = CloudProvider()
    @State private var move = false

    let proxy: GeometryProxy
    let color: Color
    let rotationStart: Double
    let duration: Double
    let alignment: Alignment

    var body: some View {
        Circle()
            .fill(color)
            .frame(height: proxy.size.height / provider.frameHeightRatio)
            .offset(provider.offset)
            .rotationEffect(.init(degrees: move ? rotationStart : rotationStart + 360))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .opacity(0.8)
            .onAppear {
                withOptionalAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                    move.toggle()
                }
            }
    }
}

struct FloatingClouds: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.appReduceMotion) private var reduceMotion
    let blur: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.generalBackground

                ZStack {
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesBottomTrailing(forScheme: scheme),
                        rotationStart: 0,
                        duration: 58,
                        alignment: .bottomTrailing
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopTrailing(forScheme: scheme),
                        rotationStart: 240,
                        duration: 46,
                        alignment: .topTrailing
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesBottomLeading(forScheme: scheme),
                        rotationStart: 120,
                        duration: 74,
                        alignment: .bottomLeading
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopLeading(forScheme: scheme),
                        rotationStart: 180,
                        duration: 64,
                        alignment: .topLeading
                    )
                    // A fifth, slower-drifting layer through the middle adds
                    // depth so the wash never reads as four flat corner blobs.
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopTrailing(forScheme: scheme).opacity(0.65),
                        rotationStart: 300,
                        duration: 95,
                        alignment: .center
                    )
                }
                .blur(radius: blur)

                AuroraShimmerOverlay()
                    .opacity(reduceMotion ? 0 : 0.55)
                    .allowsHitTesting(false)

                AuroraSparkleField()
                    .opacity(reduceMotion ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }
}

/// A slow diagonal light sweep layered above the blurred clouds. This is
/// what pushes the wash from "blurry colored blobs" to something that reads
/// as an actual aurora — a faint band of light drifting across the sky.
private struct AuroraShimmerOverlay: View {
    @State private var animate = false

    var body: some View {
        LinearGradient(
            colors: [
                .white.opacity(0),
                .white.opacity(0.07),
                .white.opacity(0),
            ],
            startPoint: animate ? .bottomLeading : .topTrailing,
            endPoint: animate ? .topTrailing : .bottomLeading
        )
        .blendMode(.plusLighter)
        .onAppear {
            withOptionalAnimation(
                Animation.easeInOut(duration: 13).repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }
}

/// Faint twinkling points of light scattered across the wash. Cheap (fixed
/// count, no per-frame layout work beyond the built-in animation) but reads
/// as genuine ambient magic rather than a static gradient.
private struct AuroraSparkleField: View {
    private struct Sparkle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let delay: Double
        let duration: Double
    }

    private let sparkles: [Sparkle] = (0 ..< 22).map { _ in
        Sparkle(
            x: CGFloat.random(in: 0 ... 1),
            y: CGFloat.random(in: 0 ... 1),
            size: CGFloat.random(in: 1.5 ... 3.5),
            delay: Double.random(in: 0 ... 4.5),
            duration: Double.random(in: 2.5 ... 5.5)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(sparkles) { sparkle in
                SparkleDot(sparkle: sparkle, containerSize: proxy.size)
            }
        }
    }

    private struct SparkleDot: View {
        let sparkle: Sparkle
        let containerSize: CGSize
        @State private var twinkle = false

        var body: some View {
            Circle()
                .fill(.white)
                .frame(width: sparkle.size, height: sparkle.size)
                .opacity(twinkle ? 0.85 : 0.12)
                .position(
                    x: sparkle.x * containerSize.width,
                    y: sparkle.y * containerSize.height
                )
                .onAppear {
                    withOptionalAnimation(
                        Animation.easeInOut(duration: sparkle.duration)
                            .repeatForever(autoreverses: true)
                            .delay(sparkle.delay)
                    ) {
                        twinkle = true
                    }
                }
        }
    }
}

struct LinearNonTransparency: View {
    @Environment(\.colorScheme) var scheme

    var gradient: Gradient {
        Gradient(colors: [
            Theme.ellipsesTopLeading(forScheme: scheme),
            Theme.ellipsesTopTrailing(forScheme: scheme)
        ])
    }

    var body: some View {
        LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

// Reusable Modifier to apply background anywhere in your app
struct AuroraBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        ZStack {
            if differentiateWithoutColor {
                Theme.differentiateWithoutColorBackground(forScheme: scheme)
                    .ignoresSafeArea()
            } else if reduceTransparency {
                LinearNonTransparency()
            } else {
                FloatingClouds()
            }

            content
        }
    }
}

extension View {
    func auroraBackground() -> some View {
        self.modifier(AuroraBackgroundModifier())
    }
}
