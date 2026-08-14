import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct PlayerBottomToolbar: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Binding var showingQueue: Bool
    let song: Song
    let onLyricsToggle: () -> Void
    let showLyrics: Bool
    var horizontalPadding: CGFloat = 48

    var body: some View {
        HStack(spacing: audioManager.isRadioMode ? 56 : 0) {
            if !audioManager.isRadioMode {
                Button {
                    onLyricsToggle()
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(showLyrics ? .primary : .secondary)
                        .frame(width: 44, height: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55, haptic: .selection))
                .accessibilityLabel(showLyrics ? "Hide Lyrics" : "Show Lyrics")
                .accessibilityValue(showLyrics ? "On" : "Off")
            }
            #if canImport(UIKit)
                ZStack {
                    Image(systemName: routeSymbolName(audioManager.routeIcon))
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    AirPlayRoutePickerView()
                        .frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)
                .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AirPlay")
                .accessibilityHint("Choose an audio output")
            #endif
            Button {
                AppHaptic.selection.play()
                showingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
            .accessibilityLabel("Playing Next")
            .accessibilityHint("Show the queue for \(song.title)")
            .accessibilityIdentifier("PlayerToolbar.PlayingNext")
        }
        .padding(.horizontal, audioManager.isRadioMode ? 0 : horizontalPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }

    private func routeSymbolName(_ name: String) -> String {
        #if canImport(UIKit)
            if UIImage(systemName: name) != nil { return name }
        #endif
        return "airplayaudio"
    }
}
