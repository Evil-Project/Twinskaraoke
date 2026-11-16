import SwiftUI

struct BandlePlayArea: View {
    @Bindable var model: BandleGameViewModel
    @Bindable var clipPlayer: BandleClipPlayer
    let onSubmit: () -> Void
    let onSkip: () -> Void
    let onSelectClip: (Int) -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.l) {
            if model.isPractice {
                Label(String(localized: "Practice · Attempts won't be recorded"), systemImage: "arrow.counterclockwise")
                    .font(AM.Font.rowCompactSubtitle)
                    .foregroundStyle(.secondary)
            }

            BandleAttemptGrid(
                attempts: model.attempts,
                currentAttempt: model.currentAttemptNumber,
                visibleAttempt: model.visibleAttemptNumber,
                isCompleted: false,
                onSelect: onSelectClip
            )

            BandleClipControls(clip: model.currentClip, isLoading: model.isLoadingClip || model.phase == .starting, player: clipPlayer)

            BandleGuessPicker(model: model, onSubmit: onSubmit, onSkip: onSkip)
                .padding(AM.Spacing.l)
                .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.card))

            if model.phase == .submitting {
                ProgressView(String(localized: "Submitting..."))
                    .accessibilityIdentifier("Bandle.Submitting")
            }
        }
    }
}
