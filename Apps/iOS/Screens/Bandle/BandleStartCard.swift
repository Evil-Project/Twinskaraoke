import SwiftUI

struct BandleStartCard: View {
    let isSignedIn: Bool
    let onStart: (Bool) -> Void
    let onPractice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.l) {
            Label(String(localized: "Six attempts. Progressively longer clips."), systemImage: "music.note.list")
                .font(AM.Font.rowTitle)
                .foregroundStyle(.primary)

            Text(String(localized: "Listen to the unlocked clip, choose a song from the official list, or skip to hear more."))
                .font(AM.Font.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !isSignedIn {
                Label(
                    String(localized: "Guests can keep progress on this device, but guest results don't appear on leaderboards."),
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .font(AM.Font.rowCompactSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button(String(localized: "Play Today's Challenge"), systemImage: "play.fill", action: startRanked)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("Bandle.PlayToday")

            if isSignedIn {
                Button(String(localized: "Play Without Leaderboard"), systemImage: "eye.slash", action: startUnranked)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("Bandle.PlayUnranked")
            }

            Button(String(localized: "Practice"), systemImage: "arrow.counterclockwise", action: onPractice)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("Bandle.Practice")
        }
        .padding(AM.Spacing.xl)
        .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.hero))
    }

    private func startRanked() {
        onStart(false)
    }

    private func startUnranked() {
        onStart(true)
    }
}
