import SwiftUI

struct ArtworkDetailAmbientBackground: View {
    let art: GalleryArt

    var body: some View {
        ZStack {
            Color.appBackground
            if let url = art.imageURL {
                RemoteArtworkImage(
                    url: url,
                    cornerRadius: 0,
                    contentMode: .fill,
                    showsLoading: false,
                    lowResURL: art.blurPreviewURL,
                    transparentBackground: true
                )
                .blur(radius: 28)
                .opacity(0.36)
                .scaleEffect(1.12)
            }
        }
        .clipped()
    }
}
