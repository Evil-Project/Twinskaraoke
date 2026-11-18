import SwiftUI

struct BandleAttemptCells: View {
    let attempts: [BandleAttempt]
    let currentAttempt: Int
    let visibleAttempt: Int
    let isCompleted: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: AM.Spacing.s) {
            ForEach(1 ... 6, id: \.self) { number in
                let attempt = attempts.first { $0.attemptNumber == number }
                // Once the game is over the grid is a summary: played attempts
                // keep their colours, the ones never needed are greyed out.
                let isUnneeded = isCompleted && attempt == nil
                let isUnlocked = !isCompleted && number <= currentAttempt
                let isPlayedSummary = isCompleted && attempt != nil
                Button {
                    // A summary cell stays a Button for its look, and
                    // VoiceOver activation ignores `allowsHitTesting`.
                    if isUnlocked { onSelect(number) }
                } label: {
                    VStack(spacing: AM.Spacing.xs) {
                        Image(systemName: attempt?.status?.systemImage ?? (isUnlocked || isUnneeded ? "waveform" : "lock.fill"))
                            .accessibilityHidden(true)
                        Text(number, format: .number)
                            .font(AM.Font.badge)
                            .accessibilityHidden(true)
                    }
                    .font(AM.Font.rowCompactTitle.bold())
                    .foregroundStyle(foreground(for: attempt?.status, isUnlocked: isUnlocked, isUnneeded: isUnneeded))
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, AM.Spacing.xs)
                    .background(
                        isUnneeded ? Color.appControlInactiveFill : background(for: attempt?.status),
                        in: .rect(cornerRadius: AM.Radius.thumb)
                    )
                    .overlay {
                        let isOnScreen = !isCompleted && number == visibleAttempt
                        RoundedRectangle(cornerRadius: AM.Radius.thumb)
                            .strokeBorder(
                                isOnScreen ? Color.appAccent : Color.appDivider,
                                // A heavier ring, not only a colour, marks the clip on screen.
                                lineWidth: isOnScreen ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                // Played attempts in the summary keep full colour, so they
                // aren't disabled (which dims them), only not tappable.
                .disabled(!isUnlocked && !isPlayedSummary)
                .allowsHitTesting(isUnlocked)
                .accessibilityRemoveTraits(isPlayedSummary ? .isButton : [])
                .accessibilityLabel(String(localized: "Attempt \(number)"))
                .accessibilityValue(
                    attempt?.status?.title
                        ?? (isUnlocked || isUnneeded ? String(localized: "Unplayed") : String(localized: "Locked"))
                )
                // The ring marks the clip on screen; VoiceOver hears it as selected.
                .accessibilityAddTraits(!isCompleted && number == visibleAttempt ? .isSelected : [])
                .accessibilityIdentifier("Bandle.Attempt.\(number)")
            }
        }
    }

    private func background(for status: BandleAttemptStatus?) -> Color {
        switch status {
        case .correct: .green
        case .incorrect: .red
        case .skipped: .appControlInactiveFill
        case nil: .appSecondaryBackground
        }
    }

    /// Played attempts sit on a solid green or red fill; locked ones recede.
    private func foreground(for status: BandleAttemptStatus?, isUnlocked: Bool, isUnneeded: Bool) -> AnyShapeStyle {
        switch status {
        case .correct, .incorrect: AnyShapeStyle(.white)
        case .skipped, nil:
            if isUnneeded {
                AnyShapeStyle(HierarchicalShapeStyle.quaternary)
            } else {
                AnyShapeStyle(isUnlocked ? HierarchicalShapeStyle.primary : .tertiary)
            }
        }
    }
}
