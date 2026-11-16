import SwiftUI

struct BandleAttemptGrid: View {
    let attempts: [BandleAttempt]
    let currentAttempt: Int
    let visibleAttempt: Int
    let isCompleted: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        // Full width when the six cells fit; scrolls at the largest text sizes.
        ViewThatFits(in: .horizontal) {
            cells
            ScrollView(.horizontal) {
                cells
            }
            .scrollIndicators(.hidden)
        }
    }

    private var cells: BandleAttemptCells {
        BandleAttemptCells(
            attempts: attempts,
            currentAttempt: currentAttempt,
            visibleAttempt: visibleAttempt,
            isCompleted: isCompleted,
            onSelect: onSelect
        )
    }
}
