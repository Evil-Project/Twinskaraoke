#if canImport(UIKit)
    import AVKit
    import SwiftUI

    struct AirPlayRoutePickerView: UIViewRepresentable {
        func makeUIView(context _: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.tintColor = .clear
            view.activeTintColor = .clear
            view.prioritizesVideoDevices = false
            view.backgroundColor = .clear
            return view
        }

        func updateUIView(_ uiView: AVRoutePickerView, context _: Context) {
            uiView.tintColor = .clear
            uiView.activeTintColor = .clear
        }
    }
#endif
