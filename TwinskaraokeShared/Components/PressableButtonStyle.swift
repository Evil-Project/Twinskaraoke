import SwiftUI

struct PressableButtonStyle: ButtonStyle {
  var scale: CGFloat = 0.97
  var dim: Double = 0.7
  var disabledOpacity: Double = 1.0
  var haptic: AppHaptic? = nil
  var pressAnimation: Animation? = nil

  func makeBody(configuration: Configuration) -> some View {
    PressableButtonBody(
      configuration: configuration,
      scale: scale,
      dim: dim,
      disabledOpacity: disabledOpacity,
      haptic: haptic,
      pressAnimation: pressAnimation
    )
  }
}

extension ButtonStyle where Self == PressableButtonStyle {
  static var watchPressable: PressableButtonStyle {
    PressableButtonStyle(
      scale: 0.96,
      dim: 0.78,
      disabledOpacity: 0.42,
      pressAnimation: .easeOut(duration: 0.16)
    )
  }
}

private struct PressableButtonBody: View {
  let configuration: ButtonStyle.Configuration
  let scale: CGFloat
  let dim: Double
  let disabledOpacity: Double
  let haptic: AppHaptic?
  let pressAnimation: Animation?
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
  @State private var wasPressed = false

  var body: some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? scale : 1.0))
      .opacity(currentOpacity)
      .animation(reduceMotion ? nil : animation, value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, isPressed in
        updatePressState(isPressed)
      }
  }

  private var currentOpacity: Double {
    guard isEnabled else { return disabledOpacity }
    return configuration.isPressed ? dim : 1.0
  }

  private var animation: Animation {
    pressAnimation ?? AppMotion.snap
  }

  private func updatePressState(_ isPressed: Bool) {
    if isPressed && !wasPressed {
      haptic?.play()
    }
    wasPressed = isPressed
  }

  private var reduceMotion: Bool {
    AppMotion.reduceMotion(
      systemReduceMotion: systemReduceMotion,
      respectPreference: respectReducedMotion
    )
  }
}
