import SwiftUI
#if canImport(UIKit)
  import SDWebImageSwiftUI
#endif

/// Apple Music–style ambient background: four album-art-tinted blobs that
/// drift and morph behind a heavy material layer. Falls back to a static
/// gradient when the artwork cannot be sampled.
struct PlayerAmbientBackground: View {
  let artworkURL: URL?
  var isPlaying: Bool = true
  @State private var palette: ArtworkPalette = .placeholder
  @State private var isVisible: Bool = false
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(isVisible && isPlaying))) {
      context in
      let t = context.date.timeIntervalSinceReferenceDate
      ZStack {
        Color(.systemBackground)
        meshLayer(time: t)
        Rectangle()
          .fill(.ultraThinMaterial)
        Rectangle()
          .fill(Color(.systemBackground).opacity(0.18))
      }
      .ignoresSafeArea()
      .animation(.easeInOut(duration: 1.2), value: palette)
    }
    .onAppear {
      isVisible = true
      loadPalette()
    }
    .onDisappear { isVisible = false }
    .onChange(of: artworkURL) { _ in loadPalette() }
  }
  private func meshLayer(time: TimeInterval) -> some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let blobRadius = max(w, h) * 0.85
      let colors = [palette.primary, palette.secondary, palette.tertiary, palette.quaternary]
      ZStack {
        ForEach(0..<4, id: \.self) { i in
          let phase = time * 0.07 + Double(i) * 1.7
          let cx = w * (0.5 + 0.42 * CGFloat(sin(phase * 1.0 + Double(i) * 0.7)))
          let cy = h * (0.5 + 0.42 * CGFloat(cos(phase * 0.8 + Double(i) * 0.4)))
          let scale = 0.85 + 0.25 * CGFloat(sin(phase * 0.6 + Double(i)))
          Circle()
            .fill(
              RadialGradient(
                colors: [colors[i].opacity(0.95), colors[i].opacity(0.0)],
                center: .center,
                startRadius: 0,
                endRadius: blobRadius
              )
            )
            .frame(width: blobRadius * 2, height: blobRadius * 2)
            .scaleEffect(scale)
            .position(x: cx, y: cy)
        }
      }
      .compositingGroup()
      .blur(radius: 30)
    }
  }
  private func loadPalette() {
    guard let url = artworkURL else {
      palette = .placeholder
      return
    }
    #if canImport(UIKit)
      SDWebImageManager.shared.loadImage(
        with: url,
        options: [.retryFailed],
        progress: nil
      ) { image, _, _, _, _, _ in
        guard let image else { return }
        let extracted = ArtworkPalette(image: image)
        DispatchQueue.main.async {
          palette = extracted
        }
      }
    #endif
  }
}
