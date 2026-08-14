import SwiftUI

struct PlayerVolumeRow: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var volumeBridgeGeneration = 0
    // In-drag volume lives here so the 60-120Hz drag updates don't publish
    // through AudioPlayerManager; the manager is committed once on drag end.
    @State private var dragVolume: Double?
    var horizontalPadding: CGFloat = 32

    private var displayVolume: Double {
        dragVolume ?? audioManager.volume
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { displayVolume },
            set: { newValue in
                if audioManager.isUserScrubbingVolume {
                    dragVolume = newValue
                } else {
                    audioManager.volume = newValue
                }
            }
        )
    }

    var body: some View {
        @Bindable var audioManager = audioManager
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            AppleMusicProgressBar(
                progress: volumeBinding,
                isScrubbing: $audioManager.isUserScrubbingVolume,
                onSeekEnd: { final in
                    audioManager.volume = final
                    dragVolume = nil
                },
                trackColor: Color.primary.opacity(0.18),
                fillColor: .primary,
                accessibilityLabel: "Volume",
                accessibilityValueText: "\(Int(displayVolume * 100)) percent",
                accessibilityHint: "Drag or swipe up and down to adjust volume."
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, horizontalPadding)
        #if canImport(UIKit)
            .background(
                SystemVolumeBridge(
                    volume: volumeBinding,
                    isUserScrubbing: $audioManager.isUserScrubbingVolume
                )
                .id(volumeBridgeGeneration)
                .frame(width: 1, height: 1)
            )
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    volumeBridgeGeneration += 1
                }
            }
        #endif
    }
}
