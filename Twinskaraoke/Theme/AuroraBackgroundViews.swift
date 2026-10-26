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
    @Environment(\.appAnimationsActive) private var animationsActive
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
                updateAnimation(shouldAnimate: shouldAnimate)
            }
            .onChange(of: shouldAnimate) { _, shouldAnimate in
                updateAnimation(shouldAnimate: shouldAnimate)
            }
    }

    private var shouldAnimate: Bool {
        animationsActive && !reduceEffects
    }

    private func updateAnimation(shouldAnimate: Bool) {
        if !shouldAnimate {
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
            .drawingGroup(opaque: false, colorMode: .linear)
            .blur(radius: blur)
        }
    }
}

struct LinearNonTransparency: View {
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
struct NweroAuroraBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Group {
            if differentiateWithoutColor {
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
struct AuroraBackgroundModifier: ViewModifier {
    private var isNwero: Bool {
        AppThemeStore.shared.definition.backdrop == .aurora
    }

    func body(content: Content) -> some View {
        ZStack {
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
