import SDWebImageSwiftUI
import SwiftUI

enum ImageCacheConfig {
  private static var didApply = false
  static func applyLimits() {
    guard !didApply else { return }
    didApply = true
    let cfg = SDImageCache.shared.config
    cfg.maxMemoryCost = 64 * 1024 * 1024
    cfg.maxMemoryCount = 60
    cfg.maxDiskSize = 256 * 1024 * 1024
    cfg.shouldCacheImagesInMemory = true
    cfg.shouldUseWeakMemoryCache = true
    SDImageCache.shared.clearMemory()
    SDWebImageDownloader.shared.config.maxConcurrentDownloads = 4
    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil, queue: .main
      ) { _ in
        SDImageCache.shared.clearMemory()
      }
    #endif
  }
  /// Cap the in-memory decoded size for shelf/grid artwork so SDWebImage doesn't
  /// hold full-resolution bitmaps for every visible tile (the 2GB footprint in
  /// recent hang reports came from oversized decoded artwork).
  static let thumbnailPixelSize = CGSize(width: 600, height: 600)
}

struct LoadingImage: View {
  let url: URL?
  var cornerRadius: CGFloat = 8
  var contentMode: ContentMode = .fill
  var showsLoading: Bool = true
  var lowResURL: URL? = nil
  var transparentBackground: Bool = false
  var body: some View {
    GeometryReader { geo in
      let pixelSize = NSValue(cgSize: thumbnailPixelSize(for: geo.size))
      ZStack {
        if !transparentBackground {
          Color(.systemGray5)
        }
        if let lowResURL {
          WebImage(url: lowResURL, context: [.imageThumbnailPixelSize: pixelSize]) { image in
            image
              .resizable()
              .aspectRatio(contentMode: contentMode)
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()
          } placeholder: { Color.clear }
        }
        WebImage(url: url, context: [.imageThumbnailPixelSize: pixelSize]) { image in
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
  private func thumbnailPixelSize(for displaySize: CGSize) -> CGSize {
    #if canImport(UIKit)
      let scale = UIScreen.main.scale
    #else
      let scale: CGFloat = 2
    #endif
    let w = max(displaySize.width, 1) * scale
    let h = max(displaySize.height, 1) * scale
    let cap = ImageCacheConfig.thumbnailPixelSize
    return CGSize(width: min(w, cap.width), height: min(h, cap.height))
  }
}

/// Animated loading indicator backed by the `LoadingImage` data asset.
/// The asset data is loaded once and shared; SDWebImage's `AnimatedImage`
/// otherwise decodes a fresh copy per instance, which is expensive when
/// many placeholders mount at the same time (carousels, grids).
private enum LoadingIndicatorAsset {
  static let data: Data = NSDataAsset(name: "LoadingImage")?.data ?? Data()
}

struct LoadingIndicator: View {
  var size: CGFloat = 48
  var body: some View {
    AnimatedImage(data: LoadingIndicatorAsset.data)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}
