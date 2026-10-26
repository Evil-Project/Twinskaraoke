import SwiftUI

@main
struct Twinskaraoke_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchDownloadAppDelegate.self) private var downloadDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue

    init() {
        #if DEBUG
        WatchPlaybackUITestFixture.prepareIfNeeded()
        #endif
        // Starts mirroring the phone's session; the watch cannot sign in alone.
        WatchAuthManager.shared.activate()
        WatchDownloads.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                // As the phone, TV and Mac roots do: shared controls such as
                // `PressableButtonStyle` and `LyricsBouncingDots` read the
                // result from the environment.
                .injectReduceMotion()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        AudioManager.shared.sleepTimer.checkExpiry()
                        WatchAuthManager.shared.refreshAccount()
                    }
                }
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
