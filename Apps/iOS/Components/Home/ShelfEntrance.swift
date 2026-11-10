import SwiftUI

/// Fades and rises a Home or New shelf into place once, staggered by its position,
/// when the loaded content first replaces the skeleton.
private struct ShelfEntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .onAppear {
                guard !appeared else { return }
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                withAnimation(
                    AppMotion.standard
                        .delay(Double(index) * 0.05)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    func shelfEntrance(index: Int) -> some View {
        modifier(ShelfEntranceModifier(index: index))
    }
}
