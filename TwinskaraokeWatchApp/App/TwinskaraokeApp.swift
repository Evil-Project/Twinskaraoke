import SwiftUI

@main
struct Twinskaraoke_Watch_AppApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    init() {
        // Starts mirroring the phone's session; the watch cannot sign in alone.
        WatchAuthManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
