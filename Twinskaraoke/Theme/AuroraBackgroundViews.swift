import SwiftUI
import Observation

@Observable
class CloudProvider {
    var offset: CGSize
    var frameHeightRatio: CGFloat

    init() {
        frameHeightRatio = CGFloat.random(in: 0.7 ..< 1.4)
        offset = CGSize(
            width: CGFloat.random(in: -150 ..< 150),
            height: CGFloat.random(in: -150 ..< 150)
        )
    }
}

struct Cloud: View {
    @State private var provider = CloudProvider()
    @Environment(\.appReduceEffects) private var reduceEffects
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
            .rotationEffect(.init(degrees: (move && !reduceEffects) ? rotationStart : rotationStart + 360))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .opacity(0.8)
            .onAppear {
                updateAnimation(shouldReduce: reduceEffects)
            }
            .onChange(of: reduceEffects) { _, shouldReduce in
                updateAnimation(shouldReduce: shouldReduce)
            }
    }

    private func updateAnimation(shouldReduce: Bool) {
        if shouldReduce {
            withOptionalAnimation(nil) { move = false }
        } else {
            move = false
            withOptionalAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                move = true
            }
        }
    }
}

struct FloatingClouds: View {
    let blur: CGFloat = 64
    private let scheme: ColorScheme = .dark

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Cloud(proxy: proxy, color: Theme.ellipsesTopLeading(forScheme: scheme), rotationStart: 0, duration: 60, alignment: .topLeading)
                Cloud(proxy: proxy, color: Theme.ellipsesBottomTrailing(forScheme: scheme), rotationStart: 90, duration: 90, alignment: .bottomTrailing)
                Cloud(proxy: proxy, color: Theme.ellipsesTopTrailing(forScheme: scheme), rotationStart: 180, duration: 75, alignment: .topTrailing)
                Cloud(proxy: proxy, color: Theme.ellipsesBottomLeading(forScheme: scheme), rotationStart: 270, duration: 105, alignment: .bottomLeading)
            }
            .blur(radius: blur)
        }
    }
}

/// A slow diagonal light sweep layered above the blurred clouds. This is
/// what pushes the wash from "blurry colored blobs" to something that reads
/// as an actual aurora — a faint band of light drifting across the sky.
private struct AuroraShimmerOverlay: View {
    @Environment(\.appReduceEffects) private var reduceEffects
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
            guard !reduceEffects else { return }
            withOptionalAnimation(
                Animation.easeInOut(duration: 13).repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
        .onChange(of: reduceEffects) { _, shouldReduce in
            if shouldReduce {
                withOptionalAnimation(nil) { animate = false }
            } else {
                withOptionalAnimation(
                    Animation.easeInOut(duration: 13).repeatForever(autoreverses: true)
                ) {
                    animate = true
                }
            }
        }
    }
}

struct LinearNonTransparency: View {
    // Nwero always renders its dark palette; see the note on FloatingClouds.
    private let scheme: ColorScheme = .dark

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

/// Picks the right Nwero backdrop for the current accessibility settings.
/// This is real, opaquely-drawn SwiftUI content — never a transparency trick
/// that tries to reveal something mounted elsewhere in the view hierarchy.
/// Each screen that uses this owns its own instance, so NavigationStack/
/// TabView can composite push/pop/tab-switch transitions normally (they rely
/// on each screen having genuine opaque content to mask the other screen
/// while animating — punching transparency through their backing views
/// breaks that masking and causes visible ghosting mid-transition).
struct NweroAuroraBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Group {
            if differentiateWithoutColor {
                // Nwero is always dark, so use the dark variant explicitly
                // rather than reading ambient colorScheme.
                Theme.differentiateWithoutColorBackground(forScheme: .dark)
            } else if reduceTransparency {
                LinearNonTransparency()
            } else {
                FloatingClouds()
            }
        }
        .ignoresSafeArea()
    }
}

// Reusable Modifier to apply background anywhere in your app
struct AuroraBackgroundModifier: ViewModifier {
    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue

    private var isNwero: Bool {
        (AppearanceMode(rawValue: appearanceMode) ?? .dark).usesAuroraBackground
    }

    func body(content: Content) -> some View {
        ZStack {
            // Only mount the animated Aurora wash when Nwero is active. On
            // every other theme, screens paint opaque fills over this
            // background anyway, so rendering it there is pure waste.
            if isNwero {
                NweroAuroraBackdrop()
            } else {
                Color.appBackground
                    .ignoresSafeArea()
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
