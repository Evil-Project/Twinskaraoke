import SwiftUI
import SDWebImageSwiftUI

struct LoadingImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                Color(white: 0.12)
                AnimatedImage(name: "vedalCoding.gif")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
            }
        }
        .resizable()
        .scaledToFill()
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
