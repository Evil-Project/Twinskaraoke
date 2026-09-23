import SwiftUI

struct ArtworkDetailMetadata: View {
    let art: GalleryArt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = trimmed(art.description) {
                ArtworkDetailSection(title: String(localized: "About"), text: description)
            }
            if let credit = trimmed(art.credit) {
                ArtworkDetailSection(title: String(localized: "Credits"), text: credit)
            }
            if let fileName = trimmed(art.fileName) {
                ArtworkDetailSection(title: String(localized: "File"), text: fileName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
