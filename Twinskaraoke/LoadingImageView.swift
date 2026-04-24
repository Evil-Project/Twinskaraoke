import SwiftUI
import SDWebImageSwiftUI

struct LoadingImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fill

    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } placeholder: {
            ZStack {
                Color(white: 0.12)
                AnimatedImage(name: "loading_first-time.webp")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
            }
        }
        .resizable()
        .aspectRatio(contentMode: contentMode)
        .cornerRadius(cornerRadius)
        .clipped()
    }
}

struct ShimmerBox: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(white: 0.17))
    }
}
