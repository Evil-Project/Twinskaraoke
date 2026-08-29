import SwiftUI

@main
struct TwinskaraokeApp: App {
    #if canImport(UIKit)
        // Supplies `supportedInterfaceOrientationsFor:`, which is what keeps the
        // app portrait everywhere except the video player. See AppOrientationGate.
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .auroraBackground()
                .preferredColorScheme(resolvedColorScheme)
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .injectReduceMotion()
                .injectHaptics()
                .tint(.appAccent)
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
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
