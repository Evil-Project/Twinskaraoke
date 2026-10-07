import SwiftUI
import UIKit

extension Color {
    init(splashHex: String) {
        let value = UInt32(splashHex.dropFirst(), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

/// Shared by the mandatory runtime and the Studio preview. No paging gestures.
struct SplashWalkthroughView: View {
    let content: SplashContent
    let index: Int
    var errorMessage: String? = nil
    var busy = false
    let back: () -> Void
    let next: () -> Void
    let complete: () -> Void
    let retry: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var slide: SplashSlide { content.slides[index] }
    private var foreground: Color { Color(splashHex: slide.textColor) }
    private var textAlignment: TextAlignment {
        switch slide.alignment { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    private var frameAlignment: Alignment {
        switch slide.alignment { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("\(content.kind == .install ? "Welcome" : "Update") · \(index + 1) of \(content.slides.count)")
                .font(.subheadline).padding()
                .accessibilityLabel("\(content.kind == .install ? "Welcome" : "Update"), slide \(index + 1) of \(content.slides.count)")
                .accessibilityIdentifier("Splash.Progress")
            GeometryReader { geometry in
                ScrollView {
                    SplashSlideRenderer(slide: slide, viewport: geometry.size)
                        .accessibilityFocused($titleFocused)
                }
                .id("\(content.fingerprint)-\(index)")
            }
            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Retry", action: retry).buttonStyle(.borderedProminent)
                        .foregroundStyle(Color(splashHex: slide.backgroundColor))
                        .accessibilityIdentifier("Splash.Retry")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { navigationButtons }
                    VStack(spacing: 12) { navigationButtons }
                }
                .disabled(busy || errorMessage != nil)
            }
            .frame(maxWidth: 680).padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foreground)
        .background(SplashSlideBackground(slide: slide).ignoresSafeArea())
        .tint(foreground)
        .interactiveDismissDisabled()
        .onChange(of: index) { _, _ in titleFocused = true }
        .onAppear { titleFocused = true }
    }
    @ViewBuilder private var navigationButtons: some View {
        if index > 0 {
            Button("Back", action: back).buttonStyle(.bordered)
                .accessibilityIdentifier("Splash.Back")
        }
        Button(index == content.slides.count - 1 ? content.finalLabel : content.nextLabel) {
            index == content.slides.count - 1 ? complete() : next()
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(Color(splashHex: slide.backgroundColor))
        .accessibilityIdentifier(index == content.slides.count - 1 ? "Splash.Complete" : "Splash.Next")
    }
}

struct SplashRootView: View {
    private let coordinator = SplashCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    private var walkthroughDirection: LayoutDirection {
        #if DEBUG
        if AppRuntime.isUITestMode && ProcessInfo.processInfo.arguments.contains("-UITestSplashRTL") { return .rightToLeft }
        #endif
        return layoutDirection
    }
    private var isStudioTest: Bool {
        #if DEBUG
        return AppRuntime.isUITestMode && ProcessInfo.processInfo.arguments.contains("-UITestSplashStudio")
        #else
        return false
        #endif
    }
    var body: some View {
        Group {
            if isStudioTest {
                #if DEBUG
                SplashStudioTestingHost()
                #endif
            } else if coordinator.isBlocking {
                if let active = coordinator.active {
                    let renderedIndex = coordinator.index
                    SplashWalkthroughView(content: active, index: renderedIndex,
                                          errorMessage: coordinator.errorMessage, busy: coordinator.isSaving,
                                          back: { coordinator.back(expectedFingerprint: active.fingerprint, expectedIndex: renderedIndex) },
                                          next: { coordinator.next(expectedFingerprint: active.fingerprint, expectedIndex: renderedIndex) },
                                          complete: { coordinator.complete(expectedFingerprint: active.fingerprint, expectedIndex: renderedIndex) },
                                          retry: coordinator.retry)
                        .environment(\.layoutDirection, walkthroughDirection)
                } else {
                    VStack(spacing: 20) {
                        if let error = coordinator.errorMessage {
                            Text(error).multilineTextAlignment(.center)
                            Button("Retry", action: coordinator.retry).buttonStyle(.borderedProminent)
                        } else { ProgressView("Loading walkthrough") }
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).ignoresSafeArea())
                }
            } else { ContentView() }
        }
        .onOpenURL { url in
            // ContentView handles links once mounted; this root owns links while gated.
            if coordinator.isBlocking, let route = AppRoute(url: url) { AppRouter.shared.open(route) }
        }
        .onAppear { if scenePhase == .active { coordinator.foreground() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { coordinator.foreground() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            coordinator.foreground()
        }
    }
}
