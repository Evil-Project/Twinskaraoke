import SwiftUI

@main
struct TwinskaraokeTVApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .tint(.appAccent)
                .preferredColorScheme(.dark)
                // Same Experiments-gated system as iOS; on tvOS they just
                // walk/climb/sit since there's no remote-friendly way to
                // drag one around (see ShimejiSpriteView).
                .shimejiSession()
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
