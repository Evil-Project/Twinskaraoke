import SwiftUI

struct ArtworkDetailMetadata: View {
    let art: GalleryArt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = trimmed(art.description) {
                ArtworkDetailSection(title: "About", text: description)
            }
            if let credit = trimmed(art.credit) {
                ArtworkDetailSection(title: "Credits", text: credit)
            }
            if let fileName = trimmed(art.fileName) {
                ArtworkDetailSection(title: "File", text: fileName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
