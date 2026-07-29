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
    @Environment(\.appReduceMotion) private var reduceMotion
    let blur: CGFloat = 64
    // Nwero always renders its dark palette, regardless of the ambient
    // colorScheme environment value (which can momentarily disagree with
    // the forced .dark scheme depending on where in the view tree this is
    // evaluated). Hardcoding this removes that whole class of bug.
    private let scheme: ColorScheme = .dark

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.generalBackground

                ZStack {
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesBottomTrailing(forScheme: scheme),
                        rotationStart: 0,
                        duration: 16,
                        alignment: .bottomTrailing
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopTrailing(forScheme: scheme),
                        rotationStart: 240,
                        duration: 13,
                        alignment: .topTrailing
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesBottomLeading(forScheme: scheme),
                        rotationStart: 120,
                        duration: 20,
                        alignment: .bottomLeading
                    )
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopLeading(forScheme: scheme),
                        rotationStart: 180,
                        duration: 18,
                        alignment: .topLeading
                    )
                    // A fifth, slower-drifting layer through the middle adds
                    // depth so the wash never reads as four flat corner blobs.
                    Cloud(
                        proxy: proxy,
                        color: Theme.ellipsesTopTrailing(forScheme: scheme).opacity(0.65),
                        rotationStart: 300,
                        duration: 26,
                        alignment: .center
                    )
                }
                .blur(radius: blur)

                AuroraShimmerOverlay()
                    .opacity(reduceMotion ? 0 : 0.55)
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
