import SwiftUI

struct ArtworkActionStrip: View {
    let url: URL?
    let saveStatus: ArtworkSaveStatus
    let onOpen: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                ArtworkActionLabel(systemImage: "arrow.up.left.and.arrow.down.right", title: "View")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))

            Button(action: onSave) {
                ArtworkSaveActionLabel(status: saveStatus)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
            .disabled(saveStatus.isSaving)

            if let url {
                ShareLink(item: url) {
                    ArtworkActionLabel(systemImage: "square.and.arrow.up", title: "Share")
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78, haptic: .selection))
            }
        }
    }
}
