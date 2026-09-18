import SwiftUI

struct PlayerVolumeRow: View {
    var horizontalPadding: CGFloat = 32

    var body: some View {
        #if canImport(UIKit)
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SystemVolumeBridge()
                    .frame(height: 44)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, horizontalPadding)
        #endif
    }
}
