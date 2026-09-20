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
        ImageCacheConfig.applyLimits()
        WatchSessionPublisher.shared.activate()
        IOSAppShortcuts.updateAppShortcutParameters()
        WidgetSnapshotPublisher.shared.start()
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
