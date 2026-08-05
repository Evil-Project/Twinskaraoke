import SwiftUI

/// Shared card shell for context-menu previews. The common visual contract
/// is a 252 pt-wide card with a 220 pt artwork area and a text label below,
/// padded 16 pt inside a Liquid Glass rounded rectangle.
///
/// Replaces the six near-identical private `XxxContextPreview` / `XxxPreview`
/// structs that duplicated the shell in `SongRow`, `LibraryView`,
/// `PlaylistDetailView`, `RadioView`, `RadioQueueRows`, and
/// `AddToPlaylistSheet`.
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