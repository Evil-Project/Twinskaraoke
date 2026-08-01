import SwiftUI

struct WatchLoadFailureState: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            WatchEmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Unable to Load",
                message: message
            )

            Button {
                WatchHaptic.play(.click)
                retryAction()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.watchPressable)
            .accessibilityHint("Retries loading this content.")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
