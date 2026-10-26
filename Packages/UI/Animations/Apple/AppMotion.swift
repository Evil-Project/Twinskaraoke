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

  /// Small indicators stay fluid without asking every ProMotion display for
  /// 120 SwiftUI tree updates per second.
  static var lightweightAnimationInterval: TimeInterval {
    1.0 / Double(min(maximumFramesPerSecond, 60))
  }

  /// Decorative motion is intentionally cheaper than direct manipulation.
  static var decorativeAnimationInterval: TimeInterval {
    1.0 / 30.0
  }

  /// Large, blurred surfaces need only a gentle cadence to read as continuous.
  static var ambientAnimationInterval: TimeInterval {
    1.0 / 20.0
  }
}

// MARK: - Active animation clock

/// Counts only active animation time, preserving phase across scrolling, scene
/// pauses and disappearances. Decorative `TimelineView` animations read their
/// elapsed time from this rather than from wall-clock `context.date`, so a
/// paused effect resumes where it stopped instead of jumping forward.
///
/// A class, held in `@State`, so starting it is a write to the object rather
/// than to the view's state. As a struct, a view inserted while its effect was
/// already meant to run — the equalizer in the row of a song that starts while
/// another is playing, a backdrop whose artwork arrives mid-song — started the
/// clock in the update that inserted it, SwiftUI dropped that state write, and
/// the effect sat frozen at its first frame until something toggled it again.
/// Nothing reads the clock outside a `TimelineView` tick, so it needs no
/// observation of its own.
nonisolated final class ActiveAnimationClock {
    private var accumulated: TimeInterval = 0
    private var activeSince: Date?

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (activeSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func setRunning(_ running: Bool, at date: Date) {
        if running {
            if activeSince == nil { activeSince = date }
        } else {
            accumulated = elapsed(at: date)
            activeSince = nil
        }
    }
}

// MARK: - Reduce Motion EnvironmentKey

struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

struct AppReduceEffectsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

struct AppAnimationsActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
    var appReduceEffects: Bool {
        get { self[AppReduceEffectsKey.self] }
        set { self[AppReduceEffectsKey.self] = newValue }
    }
    var appAnimationsActive: Bool {
        get { self[AppAnimationsActiveKey.self] }
        set { self[AppAnimationsActiveKey.self] = newValue }
    }
}

extension View {
    func injectReduceMotion() -> some View {
        ReduceMotionInjector(content: self)
    }
}
private struct ReduceMotionInjector<Content: View>: View {
    let content: Content
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    var body: some View {
        let reduceMotion = AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
        content
            .environment(\.appReduceMotion, reduceMotion)
            .environment(
                \.appReduceEffects,
                AppMotion.reduceDecorativeEffects(
                    reduceMotion: reduceMotion,
                    lowPowerModeEnabled: lowPowerModeEnabled,
                    thermalState: thermalState
                )
            )
            .environment(\.appAnimationsActive, scenePhase == .active)
            .onReceive(
                NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            ) { _ in
                lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(
                NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            ) { _ in
                thermalState = ProcessInfo.processInfo.thermalState
            }
    }
}

enum AppMotion {
  static func reduceMotion(systemReduceMotion: Bool, respectPreference: Bool) -> Bool {
    respectPreference && systemReduceMotion
  }

  static func reduceDecorativeEffects(
    reduceMotion: Bool,
    lowPowerModeEnabled: Bool,
    thermalState: ProcessInfo.ThermalState = .nominal
  ) -> Bool {
    reduceMotion
      || lowPowerModeEnabled
      || thermalState == .serious
      || thermalState == .critical
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
  static var snap: Animation { spring(response: 0.22, dampingFraction: 0.88) }
  static var quick: Animation { spring(response: 0.32, dampingFraction: 0.85) }
  static var standard: Animation { spring(response: 0.42, dampingFraction: 0.84) }
  static var gentle: Animation { spring(response: 0.58, dampingFraction: 0.85) }
  static var playful: Animation { spring(response: 0.34, dampingFraction: 0.7) }
}
