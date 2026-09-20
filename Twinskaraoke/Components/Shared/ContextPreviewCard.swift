import SwiftUI
struct ContextPreviewCard<Artwork: View, Label: View>: View {
    let artwork: Artwork
    let label: Label

    init(
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder label: () -> Label
    ) {
        self.artwork = artwork()
        self.label = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
            label
        }
        .padding(16)
        .frame(width: 252, alignment: .leading)
        .appGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}