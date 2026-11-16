import SwiftUI

struct BandleGuessPicker: View {
    @Bindable var model: BandleGameViewModel
    let onSubmit: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.m) {
            TextField(String(localized: "Search for a song..."), text: $model.guessQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .disabled(model.phase != .playing)
                .accessibilityIdentifier("Bandle.GuessField")

            if model.selectedGuess == nil, !model.guessQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                BandleGuessSuggestions(songs: Array(model.filteredSongs.prefix(6)), onSelect: model.selectGuess)
            }

            if let selectedGuess = model.selectedGuess {
                Label(selectedGuess.displayName, systemImage: "checkmark.circle.fill")
                    .font(AM.Font.rowCompactTitle)
                    .foregroundStyle(Color.appAccent)
                    .accessibilityIdentifier("Bandle.SelectedGuess")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AM.Spacing.m) {
                    submitButton
                    skipButton
                }
                VStack(spacing: AM.Spacing.m) {
                    submitButton
                    skipButton
                }
            }
        }
    }

    private var submitButton: some View {
        Button(String(localized: "Submit Guess"), systemImage: "checkmark", action: onSubmit)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmitGuess)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("Bandle.SubmitGuess")
    }

    private var skipButton: some View {
        Button(String(localized: "Skip"), systemImage: "forward.fill", action: onSkip)
            .buttonStyle(.bordered)
            .disabled(model.phase != .playing)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("Bandle.Skip")
    }
}
