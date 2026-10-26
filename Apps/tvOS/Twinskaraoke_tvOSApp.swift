import SwiftUI

@main
struct TwinskaraokeTVApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    init() { _ = TVAuthManager.shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .tint(.appAccent)
                .preferredColorScheme(.dark)
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
