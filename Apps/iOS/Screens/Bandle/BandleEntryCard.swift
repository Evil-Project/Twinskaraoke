import SwiftUI

struct BandleEntryCard: View {
    var body: some View {
        NavigationLink {
            DeferredView { BandleGameView() }
        } label: {
            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                Label(String(localized: "Daily Bandle Challenge"), systemImage: "waveform")
                    .font(AM.Font.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appAccent)

                Text(String(localized: "Guess today's song in six clips"))
                    .font(AM.Font.groupHeader)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(String(localized: "New clips and practice every day"))
                        .font(AM.Font.tileCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AM.Font.chevron)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(AM.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSecondaryBackground, in: .rect(cornerRadius: AM.Radius.hero))
            .overlay {
                RoundedRectangle(cornerRadius: AM.Radius.hero)
                    .strokeBorder(Color.appDivider, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.9, haptic: .selection))
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityIdentifier("New.BandleCard")
    }
}
