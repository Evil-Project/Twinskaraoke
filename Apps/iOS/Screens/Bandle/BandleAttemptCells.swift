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
                let isUnlocked = isCompleted || number <= currentAttempt
                Button {
                    onSelect(number)
                } label: {
                    VStack(spacing: AM.Spacing.xs) {
                        Image(systemName: attempt?.status?.systemImage ?? (isUnlocked ? "waveform" : "lock.fill"))
                            .accessibilityHidden(true)
                        Text(number, format: .number)
                            .font(AM.Font.badge)
                            .accessibilityHidden(true)
                    }
                    .font(AM.Font.rowCompactTitle.bold())
                    .foregroundStyle(foreground(for: attempt?.status, isUnlocked: isUnlocked))
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, AM.Spacing.xs)
                    .background(background(for: attempt?.status), in: .rect(cornerRadius: AM.Radius.thumb))
                    .overlay {
                        RoundedRectangle(cornerRadius: AM.Radius.thumb)
                            .strokeBorder(
                                number == visibleAttempt ? Color.appAccent : Color.appDivider,
                                // A heavier ring, not only a colour, marks the clip on screen.
                                lineWidth: number == visibleAttempt ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked)
                .accessibilityLabel(String(localized: "Attempt \(number)"))
                .accessibilityValue(attempt?.status?.title ?? (isUnlocked ? String(localized: "Unplayed") : String(localized: "Locked")))
                // The ring marks the clip on screen; VoiceOver hears it as selected.
                .accessibilityAddTraits(number == visibleAttempt ? .isSelected : [])
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
    private func foreground(for status: BandleAttemptStatus?, isUnlocked: Bool) -> AnyShapeStyle {
        switch status {
        case .correct, .incorrect: AnyShapeStyle(.white)
        case .skipped, nil: AnyShapeStyle(isUnlocked ? HierarchicalShapeStyle.primary : .tertiary)
        }
    }
}
