#if canImport(UIKit)
  import AVKit
  import SwiftUI

  /// Hidden AirPlay route picker. Rendered transparent so we can stack a custom
  /// SF Symbol on top while still letting taps fall through to the system
  /// `AVRoutePickerView`, which handles all of the picker UI.
  struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
      let view = AVRoutePickerView()
      view.tintColor = .clear
      view.activeTintColor = .clear
      view.prioritizesVideoDevices = false
      view.backgroundColor = .clear
      return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
      uiView.tintColor = .clear
      uiView.activeTintColor = .clear
    }
  }
#endif
