import SDWebImageSwiftUI
import SwiftUI

struct LoadingImage: View {
  let url: URL?
  var cornerRadius: CGFloat = 8
  var contentMode: ContentMode = .fill
  var showsLoading: Bool = true
  var lowResURL: URL? = nil
  var transparentBackground: Bool = false
  var body: some View {
    GeometryReader { geo in
      ZStack {
        if !transparentBackground {
          Color(.systemGray5)
        }
        if let lowResURL {
          WebImage(url: lowResURL) { image in
            image
              .resizable()
              .aspectRatio(contentMode: contentMode)
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()
          } placeholder: { Color.clear }
        }
        WebImage(url: url) { image in
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .transition(.opacity)
        } placeholder: {
          if showsLoading && lowResURL == nil {
            LoadingIndicator(size: min(geo.size.width, geo.size.height) * 0.5)
          } else {
            Color.clear
          }
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

/// Animated loading indicator using `Loading.webp`. Use anywhere a spinner would normally appear.
struct LoadingIndicator: View {
  var size: CGFloat = 48
  var body: some View {
    AnimatedImage(name: "Loading.webp")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}
