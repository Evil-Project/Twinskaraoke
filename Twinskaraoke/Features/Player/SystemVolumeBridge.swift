#if canImport(UIKit)
  import MediaPlayer
  import SwiftUI

  /// Hidden `MPVolumeView` we drive programmatically to forward our slider's
  /// value through to the system volume. Holds zero visual weight (`alpha`
  /// near zero, no AirPlay button) — its only job is to relay scrubbing.
  struct SystemVolumeBridge: UIViewRepresentable {
    @Binding var volume: Double
    @Binding var isUserScrubbing: Bool
    func makeUIView(context: Context) -> MPVolumeView {
      let view = MPVolumeView(frame: .zero)
      view.alpha = 0.0001
      view.showsRouteButton = false
      return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {
      guard isUserScrubbing else { return }
      DispatchQueue.main.async {
        guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        let target = Float(max(0, min(1, volume)))
        if abs(slider.value - target) > 0.005 {
          slider.setValue(target, animated: false)
          slider.sendActions(for: .valueChanged)
        }
      }
    }
  }
#endif
