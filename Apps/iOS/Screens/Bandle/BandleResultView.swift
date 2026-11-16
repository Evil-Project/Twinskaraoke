import SwiftUI

struct BandleResultView: View {
    let result: BandleResult?
    let attempts: [BandleAttempt]
    /// A practice round isn't today's result, so it isn't shared.
    let isPractice: Bool
    let onPractice: () -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.l) {
            if let result {
                if let artworkURL = result.artworkURL {
                    RemoteArtworkImage(url: artworkURL, cornerRadius: AM.Radius.hero)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: AM.Spacing.shelfTile)
                        .accessibilityHidden(true)
                }

                Image(systemName: result.won == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(AM.Font.screenTitle)
                    .foregroundStyle(result.won == true ? .green : .red)
                    .accessibilityHidden(true)

                Text(result.won == true ? String(localized: "Well done!") : String(localized: "Unlucky"))
                    .font(AM.Font.sectionHeader)

                if result.won == true {
                    Text(String(localized: "Guessed on attempt \(result.attemptNumber ?? attempts.count) of 6."))
                        .font(AM.Font.rowTitle)
                        .multilineTextAlignment(.center)
                }

                Text(result.songTitle ?? String(localized: "Answer unavailable"))
                    .font(AM.Font.heroTitle)
                    .multilineTextAlignment(.center)
                if let artist = result.artist {
                    Text(artist)
                        .font(AM.Font.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let reimbursement = result.invalidChallengeReimbursement {
                    Label(String(localized: "Challenge reimbursed · \(reimbursement) coins"), systemImage: "exclamationmark.triangle.fill")
                        .font(AM.Font.rowCompactSubtitle)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("Bandle.Reimbursement")
                }

                if !isPractice {
                    ShareLink(item: shareText(for: result)) {
                        Label(String(localized: "Share Result"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .buttonSizing(.flexible)
                    .accessibilityIdentifier("Bandle.ShareResult")
                }
            } else {
                ContentUnavailableView(
                    String(localized: "Result needs confirming"),
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(String(localized: "Pull to refresh or use Reload to confirm today's result."))
                )
            }

            practiceButton
        }
        .padding(AM.Spacing.xl)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.hero))
    }

    private var practiceButton: some View {
        Button(String(localized: "Play Again (Practice)"), systemImage: "arrow.counterclockwise", action: onPractice)
            .buttonStyle(.borderedProminent)
            .buttonSizing(.flexible)
            .accessibilityIdentifier("Bandle.PlayAgain")
    }

    private func shareText(for result: BandleResult) -> String {
        let symbols = attempts.map { attempt in
            switch attempt.status {
            case .correct: "🟩"
            case .incorrect: "🟥"
            case .skipped, nil: "⬜"
            }
        }.joined()
        let outcome = result.won == true
            ? String(localized: "\(result.attemptNumber ?? attempts.count)/6")
            : String(localized: "X/6")
        return String(localized: "Daily Bandle Challenge · \(outcome)\n\(symbols)")
    }
}
