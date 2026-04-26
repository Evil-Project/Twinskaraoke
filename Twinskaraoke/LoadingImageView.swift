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
    .cornerRadius(cornerRadius)
    .clipped()
  }
}

struct ShimmerBox: View {
  var cornerRadius: CGFloat = 8
  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(Color(.systemGray4))
  }
}
