import SwiftUI

struct ArtworkSaveActionLabel: View {
    let status: ArtworkSaveStatus

    var body: some View {
        Group {
            switch status {
            case .saving:
                Label {
                    Text("Saving")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            case .success:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Retry", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .idle:
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
        .scaledSystemFont(size: 15, weight: .semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
