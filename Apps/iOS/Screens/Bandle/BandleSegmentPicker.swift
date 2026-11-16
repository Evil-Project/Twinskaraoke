import SwiftUI

/// A segmented picker for the Bandle mode and leaderboard period. The model
/// owns the selection and changes it asynchronously, so the picker reports a
/// choice through `onSelect` and follows `selection` when the model updates.
struct BandleSegmentPicker<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    let selection: Option
    let isDisabled: Bool
    let optionTitle: (Option) -> String
    let onSelect: (Option) -> Void

    @State private var choice: Option?

    var body: some View {
        Picker(title, selection: $choice) {
            ForEach(options) { option in
                Text(optionTitle(option)).tag(Optional(option))
            }
        }
        .pickerStyle(.segmented)
        .disabled(isDisabled)
        .onChange(of: selection, initial: true) { _, newSelection in
            choice = newSelection
        }
        .onChange(of: choice) { _, newChoice in
            report(newChoice)
        }
    }

    private func report(_ newChoice: Option?) {
        guard let newChoice, newChoice != selection else { return }
        onSelect(newChoice)
    }
}
