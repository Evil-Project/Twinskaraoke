import SwiftUI

@main
struct TwinskaraokeMacApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue
    @State private var audio = MacAudioManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: resolvedLanguage.localeIdentifier))
                .environment(audio)
                .tint(.appAccent)
                .injectReduceMotion()
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            // Transport in the menu bar, with the shortcuts Mac users expect
            // from a media app. This is the main affordance Catalyst couldn't
            // have given us for free.
            CommandMenu("Playback") {
                Button(audio.isPlaying ? "Pause" : "Play") {
                    audio.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(audio.currentSong == nil)

                Button("Next") { audio.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!audio.canPlayNext)

                Button("Previous") { audio.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!audio.canPlayPrevious)

                Divider()

                Picker("Repeat Mode", selection: Bindable(audio).playbackMode) {
                    ForEach(MacPlaybackMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: languageMode) ?? .system
    }
}
