import AppIntents
import SwiftUI

@main
struct TwinskaraokeApp: App {
    #if canImport(UIKit)
        // Supplies `supportedInterfaceOrientationsFor:`, which is what keeps
        // iPhone portrait everywhere except the video player. iPad keeps the
        // four orientations its Info.plist declares. See AppOrientationGate.
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    init() {
        AppPerformance.event("App Initialization")
        if AppRuntime.isUITestMode,
           ProcessInfo.processInfo.arguments.contains("-UITestResetRecentlyPlayed")
        {
            RecentlyPlayedStore.resetPersistedHistoryForUITesting()
        }
        ImageCacheConfig.applyLimits()
        // Mirrors the signed-in session to the paired watch, which has no way
        // to sign in on its own. No-op on devices that can't pair one.
        WatchSessionPublisher.shared.activate()
        AppThemeStore.shared.apply(AppThemeStore.shared.definition)
        WidgetSnapshotPublisher.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            SplashRootView()
                .auroraBackground()
                .preferredColorScheme(resolvedColorScheme)
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .injectReduceMotion()
                .injectHaptics()
                .tint(.appAccent)
                .onChange(of: appearanceMode) { _, mode in
                    AppThemeStore.shared.applySelection(mode)
                }
                .shimejiSession()
                .onAppear {
                    DebugLogger.log(
                        "Display refresh rate: \(DisplayRefreshRate.maximumFramesPerSecond) fps max",
                        category: .ui
                    )
                    DebugLogger.log(
                        "Appearance debug — stored: \(appearanceMode), resolvedColorScheme: \(String(describing: resolvedColorScheme))",
                        category: .ui
                    )
                }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        AppThemeStore.shared.definition.colorScheme
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
