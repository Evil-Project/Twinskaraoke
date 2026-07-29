import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

@main
struct TwinskaraokeApp: App {
    @AppStorage("nk.appearance") private var appearanceMode: String = AppearanceMode.dark.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    init() {
        ImageCacheConfig.applyLimits()
        #if canImport(UIKit)
            let accent = UIColor(red: 0.99, green: 0.19, blue: 0.35, alpha: 1)
            UIView.appearance().tintColor = accent
            UIWindow.appearance().tintColor = accent
            UINavigationBar.appearance().tintColor = accent
            UITabBar.appearance().tintColor = accent
            UISwitch.appearance().onTintColor = accent
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .auroraBackground()
                .preferredColorScheme(resolvedColorScheme)
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .injectReduceMotion()
                .tint(.appAccent)
                .onAppear {
                    DebugLogger.log(
                        "Display refresh rate: \(DisplayRefreshRate.maximumFramesPerSecond) fps max",
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
