import SwiftUI

#if os(iOS)
  import AVFoundation
  import CoreHaptics
  import UIKit
#endif
enum AppHaptics {
  static let storageKey = "nk.hapticsEnabled"
  static let strengthStorageKey = "nk.hapticStrength"
  static var isEnabled: Bool {
    guard UserDefaults.standard.object(forKey: storageKey) != nil else { return true }
    return UserDefaults.standard.bool(forKey: storageKey)
  }

  static var strength: AppHapticStrength {
    guard let raw = UserDefaults.standard.string(forKey: strengthStorageKey),
          let strength = AppHapticStrength(rawValue: raw)
    else { return .default }
    return strength
  }
}
enum AppHapticStrength: String, CaseIterable, Identifiable, Sendable {
  case light
  case medium
  case strong
  case heavy
  static let `default`: AppHapticStrength = .medium

  var id: String { rawValue }

  var label: String {
    switch self {
    case .light: "Light"
    case .medium: "Medium"
    case .strong: "Strong"
    case .heavy: "Heavy"
    }
  }
  var intensityScale: CGFloat {
    switch self {
    case .light: 0.78
    case .medium: 1.0
    case .strong, .heavy: 1.0
    }
  }
  var usesCoreHapticsImpacts: Bool { self == .strong || self == .heavy }
  var bodyScale: Double {
    switch self {
    case .light, .medium: 0
    case .strong: 1.0
    case .heavy: 1.75
    }
  }
  var usesImpactForSelection: Bool { self != .light }
  var rungBoost: Int {
    switch self {
    case .light, .medium: 0
    case .strong, .heavy: 1
    }
  }
}

struct AppHapticsEnabledKey: EnvironmentKey {
  static let defaultValue: Bool = true
}

extension EnvironmentValues {
  var appHapticsEnabled: Bool {
    get { self[AppHapticsEnabledKey.self] }
    set { self[AppHapticsEnabledKey.self] = newValue }
  }
}

extension View {
  func injectHaptics() -> some View {
    HapticsInjector(content: self)
  }
  func toggleHaptic(_ value: Bool) -> some View {
    onChange(of: value) { _, isOn in
      (isOn ? AppHaptic.commit : AppHaptic.dismiss).play()
    }
  }
  func selectionHaptic<T: Equatable>(_ value: T) -> some View {
    onChange(of: value) { _, _ in AppHaptic.selection.play() }
  }
}
private struct HapticsInjector<Content: View>: View {
  let content: Content
  @AppStorage(AppHaptics.storageKey) private var hapticsEnabled: Bool = true
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    content
      .environment(\.appHapticsEnabled, hapticsEnabled)
      .onChange(of: scenePhase) { _, phase in
        #if os(iOS)
          switch phase {
          case .active:
            HapticEngine.shared.wake()
          case .background:
            HapticEngine.shared.sleep()
          default:
            break
          }
        #endif
      }
  }
}
enum AppHaptic {
  case selection
  case detent
  case grab
  case commit
  case dismiss
  case boundary
  case success
  case warning
  case error
  case celebrate

  func play() {
    #if os(iOS)
      guard AppHaptics.isEnabled else { return }
      HapticEngine.shared.play(self)
    #endif
  }
  func prepare() {
    #if os(iOS)
      guard AppHaptics.isEnabled else { return }
      HapticEngine.shared.prepare(self)
    #endif
  }
}

#if os(iOS)
  final class HapticEngine {
    static let shared = HapticEngine()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static func detentMinimumInterval(for strength: AppHapticStrength) -> TimeInterval {
      switch strength {
      case .light, .medium: 0.05
      case .strong: 0.055
      case .heavy: 0.07
      }
    }
    private static let systemRateLimitInterval: TimeInterval = 1.0 / 20.0
    private var lastImpactTime: TimeInterval = 0
    private func allowsImpact(minimumInterval interval: TimeInterval) -> Bool {
      let now = ProcessInfo.processInfo.systemUptime
      guard now - lastImpactTime >= interval else { return false }
      lastImpactTime = now
      return true
    }

    private var engine: CHHapticEngine?
    private var enginePrepared = false
    private var engineGeneration = 0

    struct ImpactKey: Hashable {
      let haptic: AppHaptic
      let strength: AppHapticStrength
    }
    private var impactPlayers: [ImpactKey: CHHapticPatternPlayer] = [:]

    private init() {}

    func play(_ haptic: AppHaptic) {
      let strength = AppHaptics.strength
      switch haptic {
      case .detent:
        playDetent(strength: strength)
      case .success:
        notificationGenerator.notificationOccurred(.success)
      case .warning:
        notificationGenerator.notificationOccurred(.warning)
      case .error:
        notificationGenerator.notificationOccurred(.error)
      case .celebrate:
        playCelebrate()
      case .selection where !strength.usesImpactForSelection:
        guard allowsImpact(minimumInterval: Self.systemRateLimitInterval) else { return }
        selectionGenerator.selectionChanged()
      case .selection, .grab, .commit, .dismiss, .boundary:
        playImpact(haptic, strength: strength)
      }
    }
    private func playImpact(
      _ haptic: AppHaptic,
      strength: AppHapticStrength,
      minimumInterval: TimeInterval? = nil
    ) {
      let interval = max(minimumInterval ?? 0, Self.systemRateLimitInterval)
      if haptic == .commit {
        lastImpactTime = ProcessInfo.processInfo.systemUptime
      } else {
        guard allowsImpact(minimumInterval: interval) else { return }
      }
      if haptic != .detent,
         strength.usesCoreHapticsImpacts,
         playCoreImpact(haptic, strength: strength) {
        return
      }
      let (generator, intensity) = resolve(haptic, strength: strength)
      generator.impactOccurred(intensity: intensity)
      generator.prepare()
    }
    private func coreProfile(for haptic: AppHaptic) -> (intensity: Float, sharpness: Float, body: TimeInterval)? {
      switch haptic {
      case .selection: (0.85, 0.55, 0.012)
      case .grab: (0.85, 0.20, 0.045)
      case .dismiss: (0.90, 0.45, 0.020)
      case .commit: (1.00, 0.70, 0.045)
      case .detent: (1.00, 1.00, 0)
      case .boundary: (1.00, 0.35, 0.075)
      default: nil
      }
    }

    private func playCoreImpact(_ haptic: AppHaptic, strength: AppHapticStrength) -> Bool {
      guard let profile = coreProfile(for: haptic) else { return false }
      startEngineIfNeeded()
      guard supportsCoreHaptics, engine != nil else { return false }

      let key = ImpactKey(haptic: haptic, strength: strength)
      guard let player = impactPlayer(for: key, profile: profile, strength: strength) else {
        return false
      }
      do {
        try player.start(atTime: CHHapticTimeImmediate)
        return true
      } catch {
        impactPlayers.removeAll()
        return false
      }
    }
    private func impactPlayer(
      for key: ImpactKey,
      profile: (intensity: Float, sharpness: Float, body: TimeInterval),
      strength: AppHapticStrength
    ) -> CHHapticPatternPlayer? {
      if let cached = impactPlayers[key] { return cached }
      guard let engine else { return nil }

      var events = [
        CHHapticEvent(
          eventType: .hapticTransient,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: profile.intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: profile.sharpness),
          ],
          relativeTime: 0
        )
      ]
      let body = profile.body * strength.bodyScale
      if body > 0 {
        events.append(
          CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
              CHHapticEventParameter(parameterID: .hapticIntensity, value: profile.intensity),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: profile.sharpness * 0.5),
            ],
            relativeTime: 0,
            duration: body
          )
        )
      }

      do {
        let player = try engine.makePlayer(with: try CHHapticPattern(events: events, parameters: []))
        impactPlayers[key] = player
        return player
      } catch {
        return nil
      }
    }
    private var ladder: [UIImpactFeedbackGenerator] {
      [softGenerator, lightGenerator, mediumGenerator, rigidGenerator, heavyGenerator]
    }

    private func resolve(
      _ haptic: AppHaptic,
      strength: AppHapticStrength
    ) -> (UIImpactFeedbackGenerator, CGFloat) {
      let baseRung: Int
      let trim: CGFloat
      let cap: Int
      switch haptic {
      case .grab:
        baseRung = 0; trim = 1.0; cap = 4
      case .selection:
        baseRung = 1; trim = 0.85; cap = 4
      case .dismiss:
        baseRung = 1; trim = 1.0; cap = 4
      case .commit:
        baseRung = 2; trim = 1.0; cap = 3
      case .detent:
        baseRung = 3; trim = 0.9; cap = 3
      case .boundary:
        baseRung = 4; trim = 1.0; cap = 4
      default:
        baseRung = 2; trim = 1.0; cap = 4
      }

      let promoted = baseRung + strength.rungBoost
      let rung = min(cap, min(ladder.count - 1, promoted))
      let intensity = min(1.0, max(0.1, strength.intensityScale * trim))
      return (ladder[rung], intensity)
    }

    func prepare(_ haptic: AppHaptic) {
      let strength = AppHaptics.strength
      switch haptic {
      case .success, .warning, .error:
        notificationGenerator.prepare()
      case .celebrate:
        startEngineIfNeeded()
      case .selection where !strength.usesImpactForSelection:
        selectionGenerator.prepare()
      case .selection, .detent, .grab, .commit, .dismiss, .boundary:
        resolve(haptic, strength: strength).0.prepare()
      }
    }

    private func playDetent(strength: AppHapticStrength) {
      playImpact(
        .detent,
        strength: strength,
        minimumInterval: Self.detentMinimumInterval(for: strength)
      )
    }
    func wake() {
      guard enginePrepared || AppHaptics.strength.usesCoreHapticsImpacts else { return }
      startEngineIfNeeded()
    }

    func sleep() {
      impactPlayers.removeAll()
      let stopping = engine
      engine = nil
      enginePrepared = false
      engineGeneration += 1
      stopping?.stop()
    }

    private var supportsCoreHaptics: Bool {
      CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private func startEngineIfNeeded() {
      guard supportsCoreHaptics else { return }
      enginePrepared = true

      if let engine {
        try? engine.start()
        return
      }

      do {
        let engine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
        engine.playsHapticsOnly = true
        engineGeneration += 1
        let generation = engineGeneration
        engine.stoppedHandler = { @Sendable [weak self] _ in
          Task { @MainActor in
            guard let self, self.engineGeneration == generation else { return }
            self.impactPlayers.removeAll()
            self.engine = nil
          }
        }
        engine.resetHandler = { @Sendable [weak self] in
          Task { @MainActor in
            guard let self, self.engineGeneration == generation else { return }
            self.impactPlayers.removeAll()
            try? self.engine?.start()
          }
        }
        try engine.start()
        self.engine = engine
      } catch {
        impactPlayers.removeAll()
        engine = nil
      }
    }
    private func playCelebrate() {
      startEngineIfNeeded()

      guard supportsCoreHaptics, let engine else {
        notificationGenerator.notificationOccurred(.success)
        return
      }

      let swell = CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
        ],
        relativeTime: 0,
        duration: 0.18
      )
      let accent = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
        ],
        relativeTime: 0.18
      )
      let rise = CHHapticParameterCurve(
        parameterID: .hapticIntensityControl,
        controlPoints: [
          .init(relativeTime: 0, value: 0.4),
          .init(relativeTime: 0.18, value: 1.0),
        ],
        relativeTime: 0
      )

      do {
        let pattern = try CHHapticPattern(events: [swell, accent], parameterCurves: [rise])
        try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
      } catch {
        notificationGenerator.notificationOccurred(.success)
      }
    }
  }

#endif
