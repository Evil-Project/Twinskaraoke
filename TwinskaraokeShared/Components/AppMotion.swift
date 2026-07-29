import SwiftUI

#if os(iOS)
  import UIKit
#endif

enum DisplayRefreshRate {

  static var maximumFramesPerSecond: Int {
    #if os(iOS)
      let sceneMaximum = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
        .max()
      return max(sceneMaximum ?? 60, 60)
    #else
      return 60
    #endif
  }

  /// Full display rate — 120Hz on ProMotion — for small always-moving elements
  /// (spinners, bouncing dots) whose choppiness is visible next to smooth scrolling.
  static var lightweightAnimationInterval: TimeInterval {
    1.0 / Double(maximumFramesPerSecond)
  }

  /// Decorative ambience (equalizer bars). 60fps reads as fluid; full display
  /// rate would spend battery on motion nobody tracks closely.
  static var decorativeAnimationInterval: TimeInterval {
    1.0 / 60.0
  }
}

// MARK: - Reduce Motion EnvironmentKey

struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Whether reduce-motion should be respected, combining the system
    /// accessibility setting with the user's in-app preference.
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// Injects the computed `appReduceMotion` flag into the environment so
    /// child views can read `@Environment(\.appReduceMotion)` instead of
    /// repeating the `@AppStorage + @Environment + AppMotion.reduceMotion`
    /// boilerplate.  Apply once at the root of each view tree.
    func injectReduceMotion() -> some View {
        ReduceMotionInjector(content: self)
    }
}

// Generic over Content rather than boxing in AnyView: this wraps the root of
// every view tree, and an AnyView there erases the static type SwiftUI relies
// on to diff the whole app structurally.
private struct ReduceMotionInjector<Content: View>: View {
    let content: Content
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        content.environment(\.appReduceMotion, AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        ))
    }
}

// MARK: - AppMotion

enum AppMotion {
  static func reduceMotion(systemReduceMotion: Bool, respectPreference: Bool) -> Bool {
    respectPreference && systemReduceMotion
  }

  static func duration(_ seconds: TimeInterval) -> TimeInterval {
    max(0, seconds)
  }

  static func easeInOut(duration seconds: TimeInterval) -> Animation {
    .easeInOut(duration: duration(seconds))
  }

  static func easeOut(duration seconds: TimeInterval) -> Animation {
    .easeOut(duration: duration(seconds))
  }

  static func linear(duration seconds: TimeInterval) -> Animation {
    .linear(duration: duration(seconds))
  }

  static func spring(response: TimeInterval, dampingFraction: Double) -> Animation {
    .spring(response: duration(response), dampingFraction: dampingFraction)
  }

  // MARK: - Semantic motion scale

  // One shared physics family so every interaction feels tuned by the same hand.
  // Pick by role, not by taste-per-callsite:

  /// Small state flips: icons, badges, toggles, selection feedback.
  static var snap: Animation { spring(response: 0.22, dampingFraction: 0.88) }

  /// The workhorse: row/list changes, control state, chrome reveals.
  static var quick: Animation { spring(response: 0.32, dampingFraction: 0.85) }

  /// Content-level moves: section reflows, layout swaps, sheets' inner content.
  static var standard: Animation { spring(response: 0.42, dampingFraction: 0.84) }

  /// Large surfaces: hero artwork, full-screen layout shifts, lyric scrolling.
  static var gentle: Animation { spring(response: 0.58, dampingFraction: 0.85) }

  /// Deliberately bouncy celebratory moments.
  static var playful: Animation { spring(response: 0.34, dampingFraction: 0.7) }
}
