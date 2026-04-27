//
//  LoadingImageView.swift
//  Twinskaraoke
//
//  Created by xiaoyuan on 2026/4/26.
//
import SDWebImageSwiftUI
import SwiftUI

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
        Color(.systemGray5)
        AnimatedImage(name: "LoadingFirstTime.webp")
          .resizable()
          .scaledToFit()
          .frame(width: 48, height: 48)
      }
    }
    .resizable()
    .aspectRatio(contentMode: contentMode)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct ShimmerBox: View {
  var cornerRadius: CGFloat = 8
  @State private var phase: CGFloat = -1
  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(Color(.systemGray5))
      .overlay(
        GeometryReader { geo in
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0), location: 0),
              .init(color: .white.opacity(0.35), location: 0.5),
              .init(color: .white.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: geo.size.width * 0.6)
          .offset(x: phase * geo.size.width * 1.6)
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .onAppear {
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
          phase = 1
        }
      }
  }
}
