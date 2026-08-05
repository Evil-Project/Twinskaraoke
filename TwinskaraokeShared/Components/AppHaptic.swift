import SwiftUI

#if os(iOS)
  import AVFoundation
  import CoreHaptics
  import UIKit
#endif

// MARK: - Haptics preference

/// Whether haptics should fire, combining the user's in-app preference with
/// the hardware's ability to play them.  Mirrors `AppMotion.reduceMotion`.
enum AppHaptics {
  static let storageKey = "nk.hapticsEnabled"
  static let strengthStorageKey = "nk.hapticStrength"

  /// Read straight from `UserDefaults` rather than `@AppStorage` because
  /// `AppHaptic.play()` is called from plain model code and gesture callbacks,
  /// not only from `View` bodies.  Absent key means "on" — `bool(forKey:)`
  /// would report `false` for a preference the user has never touched.
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

/// A global weight applied on top of every role.  The role decides the
/// *character* of a haptic (sharp tick, soft swell, solid thud); this decides
/// how hard it lands.  Roles keep their relative ordering at every level, so
/// raising the baseline never collapses two roles into the same sensation.
enum AppHapticStrength: String, CaseIterable, Identifiable, Sendable {
  case light
  case medium
  case strong
  case heavy

  /// `medium` sits where `strong` used to before the scale was rebalanced: full
  /// intensity on every role and real impacts for taps, which is already firmer
  /// than most iOS apps ship. `strong` and `heavy` now genuinely earn their
  /// names via CoreHaptics, so they are opt-in rather than the starting point.
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

  /// Scales role intensity on the UIKit path.  Capped at 1.0 by the generators,
  /// which is precisely why the top two levels leave that path entirely.
  var intensityScale: CGFloat {
    switch self {
    case .light: 0.78
    case .medium: 1.0
    case .strong, .heavy: 1.0
    }
  }

  /// `UIImpactFeedbackGenerator` tops out at `.heavy` @ 1.0, and several roles
  /// already sit there — so the top two levels render through CoreHaptics
  /// instead, where intensity, sharpness and duration are continuous.  That is
  /// the only way to go past the canned ceiling *and* keep roles separable;
  /// stacking more roles onto five discrete rungs just collides them.
  var usesCoreHapticsImpacts: Bool { self == .strong || self == .heavy }

  /// Length multiplier for the continuous layer stacked under each transient.
  /// A transient alone is a click; adding sustain under it is what reads as
  /// weight, and it is where `heavy` gets its extra punch once intensity is
  /// already pinned at maximum.
  var bodyScale: Double {
    switch self {
    case .light, .medium: 0
    case .strong: 1.0
    case .heavy: 1.75
    }
  }

  /// Only the gentlest level keeps the plain selection tick.  It has no
  /// intensity control, so it is the one texture that cannot be cranked.
  var usesImpactForSelection: Bool { self != .light }

  /// How far up the canned-generator ladder to climb.  This is the *fallback*
  /// path for the top two levels — hardware without CoreHaptics, or an engine
  /// that failed to start — so it still has to get heavier with the baseline.
  /// `heavy` deliberately stops at the same boost as `strong`.  Five rungs
  /// cannot hold six roles apart once they are pushed harder than this — they
  /// pile against the top and collide.  Heavy earns its extra weight from
  /// `bodyScale` on the CoreHaptics path, so the canned fallback simply tops
  /// out rather than smearing roles together.
  var rungBoost: Int {
    switch self {
    case .light, .medium: 0
    case .strong, .heavy: 1
    }
  }
}

// MARK: - Haptics EnvironmentKey

struct AppHapticsEnabledKey: EnvironmentKey {
  static let defaultValue: Bool = true
}

extension EnvironmentValues {
  /// Whether haptics are switched on for this view tree.  Read this when a
  /// view needs to *branch* on the preference (e.g. to skip arming a
  /// generator); firing through `AppHaptic` already honours it.
  var appHapticsEnabled: Bool {
    get { self[AppHapticsEnabledKey.self] }
    set { self[AppHapticsEnabledKey.self] = newValue }
  }
}

extension View {
  /// Injects the haptics preference into the environment and keeps the haptic
  /// engine's lifecycle tied to the scene.  Apply once at the root, next to
  /// `injectReduceMotion()`.
  func injectHaptics() -> some View {
    HapticsInjector(content: self)
  }

  /// Plays a tick for a tap that navigates.
  ///
  /// `NavigationLink` exposes no action closure to hang a haptic on, and a
  /// custom `ButtonStyle` is *not* a reliable substitute: SwiftUI swaps in its
  /// own style inside toolbars and some list contexts, which silently discards
  /// the style's haptic along with it.  A simultaneous `TapGesture` runs
  /// alongside the link's own recognizer without consuming the tap, so
  /// navigation still happens.
  ///
  /// `TapGesture` only recognises a press with no travel, so this does not
  /// compete with scrolling or with drag-driven transitions.
  func navigationTapHaptic(_ haptic: AppHaptic = .selection) -> some View {
    simultaneousGesture(TapGesture().onEnded { haptic.play() })
  }

  /// Plays a flip whenever a bound `Bool` changes — for `Toggle`s built on a
  /// plain binding, which SwiftUI gives no action hook of their own.
  ///
  /// Switching something on is a commit; switching it off is the gentler
  /// counterpart, matching how the rest of the app treats forward versus back.
  /// Do **not** add this to a `Toggle` whose binding already plays a haptic in
  /// its setter, or the flip fires twice.
  func toggleHaptic(_ value: Bool) -> some View {
    onChange(of: value) { _, isOn in
      (isOn ? AppHaptic.commit : AppHaptic.dismiss).play()
    }
  }

  /// Plays a tick whenever a picker's selection changes.  `Picker` has no
  /// action closure, and its rows are system-drawn, so the bound value is the
  /// only place a change surfaces.
  func selectionHaptic<T: Equatable>(_ value: T) -> some View {
    onChange(of: value) { _, _ in AppHaptic.selection.play() }
  }
}

// Generic over Content for the same reason `ReduceMotionInjector` is: this
// wraps the root of the view tree, and an AnyView there erases the static type
// SwiftUI relies on to diff the whole app structurally.
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

// MARK: - AppHaptic

/// One shared feel family so every interaction feels tuned by the same hand.
/// Pick by **role**, not by texture-per-callsite — the texture behind a role
/// can be retuned here once and every call site inherits it.
enum AppHaptic {
  /// Discrete selection moved: row tap, tab change, segment switch, filter
  /// applied, picker step.  The most common case by far.
  case selection

  /// A continuous drag crossed a notch: scrub detents, reorder steps, zoom
  /// stops.  Rate-limited, so a fast drag *ticks* instead of buzzing.
  case detent

  /// A control was physically picked up: drag begins, long-press arms, a
  /// sheet grabs its handle.  Soft, so it reads as contact rather than a click.
  case grab

  /// A control committed to its action: primary button, play/pause, send.
  case commit

  /// The gentle counterpart to `commit` — a surface closed, an action
  /// cancelled, a setting switched off.  Backing out should never feel as
  /// weighty as going forward.
  case dismiss

  /// Travel stopped against a limit: scrub end-stop, list edge, cap reached.
  /// Rigid, so it reads as hitting something solid.
  case boundary

  /// The work finished and the result is good.
  case success

  /// The work finished but something needs attention.
  case warning

  /// The work failed.
  case error

  /// A rare, earned moment — a custom CoreHaptics texture rather than a canned
  /// system thump.  Reserve it; overuse is what makes haptics feel cheap.
  case celebrate

  func play() {
    #if os(iOS)
      guard AppHaptics.isEnabled else { return }
      HapticEngine.shared.play(self)
    #endif
  }

  /// Warms the generator this role uses so the *next* `play()` fires without
  /// the ~100ms spin-up latency.  Call at the start of a gesture — on
  /// `onLongPressGesture`'s `onPressingChanged`, or the first tick of a drag.
  /// Free to call repeatedly; the system coalesces it.
  func prepare() {
    #if os(iOS)
      guard AppHaptics.isEnabled else { return }
      HapticEngine.shared.prepare(self)
    #endif
  }
}

#if os(iOS)

  // MARK: - HapticEngine

  /// Owns the feedback generators and the CoreHaptics engine.
  ///
  /// The generators are cached rather than allocated per call: a
  /// `UIFeedbackGenerator` only pays off if it is alive long enough to keep the
  /// Taptic Engine warm, and `prepare()` immediately followed by a fire is
  /// indistinguishable from not preparing at all.
  final class HapticEngine {
    static let shared = HapticEngine()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Detents arrive as fast as a drag delivers touches — far faster than the
    /// Taptic Engine can render distinctly.  Below this spacing the ticks blur
    /// into a buzz, which reads as noise rather than texture.
    ///
    /// The spacing widens with strength on purpose: a heavier tap rings for
    /// longer, so ticks that stayed crisp at the light baseline would smear
    /// into each other at the heavy one.
    /// Spacing exists so ticks stay perceptually distinct — a heavier tap rings
    /// longer and smears if crowded — **not** to satisfy the server's 32Hz
    /// ceiling. Starving the rate to 12.5Hz was measured on device and did not
    /// stop the rate-limit log; it only made the scrub coarser. See the
    /// `prepare()` note in `playImpact` for what the log actually tracks.
    private static func detentMinimumInterval(for strength: AppHapticStrength) -> TimeInterval {
      switch strength {
      case .light, .medium: 0.05
      case .strong: 0.055
      case .heavy: 0.07
      }
    }

    /// The haptic server drops anything sent faster than 32Hz and logs
    /// "Message send exceeds rate-limit threshold and will be dropped".
    ///
    /// This floor applies to *every* impact, not just detents, because the
    /// server's budget is shared: two individually-reasonable sources can breach
    /// it together. Dropping our own overflow is strictly better than letting the
    /// server drop it — one skipped tick is imperceptible, whereas a flooded
    /// server discards them in audible clumps and the scrub feels uneven.
    ///
    /// Notification roles and `celebrate` bypass this: they are rare, carry real
    /// meaning, and must never be swallowed by a burst of ticks.
    ///
    /// 20Hz, matched to the detent spacing rather than left looser.
    ///
    /// Measured on device: with the generator kept warm, a peak scrub still
    /// tripped the server, and the tightest observed spacing was 33ms — the old
    /// 1/30s value here, not the 40ms detent interval. A `.boundary` (scrub
    /// end-stop) or `.grab` was interleaving with detents and slipping through at
    /// the looser floor while every role individually respected its own spacing.
    ///
    /// All roles share one clock, so **the loosest interval sets the real
    /// ceiling** — a per-role interval is only ever a lower bound. Matching this
    /// to the detent spacing closes that seam, and no hand-driven interaction is
    /// faster than 20Hz, so discrete taps are unaffected.
    private static let systemRateLimitInterval: TimeInterval = 1.0 / 20.0
    private var lastImpactTime: TimeInterval = 0

    /// Returns false when this impact would breach `interval` since the last one.
    private func allowsImpact(minimumInterval interval: TimeInterval) -> Bool {
      let now = ProcessInfo.processInfo.systemUptime
      guard now - lastImpactTime >= interval else { return false }
      lastImpactTime = now
      return true
    }

    private var engine: CHHapticEngine?
    private var enginePrepared = false

    struct ImpactKey: Hashable {
      let haptic: AppHaptic
      let strength: AppHapticStrength
    }

    /// Rebuilt lazily; must be dropped whenever the engine resets, because a
    /// player is bound to the engine instance that created it.
    private var impactPlayers: [ImpactKey: CHHapticPatternPlayer] = [:]

    private init() {}

    // MARK: Playback

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
        // The one texture with no intensity control, so it only survives at
        // the gentlest baseline; above it a real impact takes over.  Still
        // throttled: this path bypasses `playImpact`, and the server's 32Hz
        // budget counts selection ticks the same as impacts.
        guard allowsImpact(minimumInterval: Self.systemRateLimitInterval) else { return }
        selectionGenerator.selectionChanged()
      case .selection, .grab, .commit, .dismiss, .boundary:
        playImpact(haptic, strength: strength)
      }
    }

    /// CoreHaptics when the baseline calls for it, canned generators otherwise.
    /// Any CoreHaptics failure falls through rather than dropping the haptic —
    /// a weaker tap beats no tap.
    private func playImpact(
      _ haptic: AppHaptic,
      strength: AppHapticStrength,
      minimumInterval: TimeInterval? = nil
    ) {
      // Every impact funnels through here, which makes this the one place the
      // shared 32Hz server budget can be enforced.  Roles that want to be
      // sparser than the floor (detents) pass their own spacing.
      let interval = max(minimumInterval ?? 0, Self.systemRateLimitInterval)
      guard allowsImpact(minimumInterval: interval) else { return }
      // `.detent` stays on the canned generator at *every* strength.
      // `UIImpactFeedbackGenerator` is the API built for rapid repeated feedback
      // and can be held armed between ticks (see the `prepare()` call below),
      // whereas a CoreHaptics pattern player has to be started afresh for each
      // one. `.rigid` at full intensity is already the sharpest canned texture,
      // so the loss is small and the trade is worth it on a role that fires
      // ~20x a second.
      if haptic != .detent,
         strength.usesCoreHapticsImpacts,
         playCoreImpact(haptic, strength: strength) {
        return
      }
      let (generator, intensity) = resolve(haptic, strength: strength)
      generator.impactOccurred(intensity: intensity)
      // Re-arm immediately so the generator's reporter does not idle out before
      // the next tick.
      //
      // Measured on device: throttling *harder* made things worse — at 50ms gaps
      // the server complained ~2.2x per impact, at 83ms gaps ~2.5x, and at 10Hz
      // (25Hz effective, comfortably under the 32Hz ceiling) it still complained.
      // Complaints therefore do not scale with our fire rate; they track the
      // `Reporter disconnected or already stopped` churn, which grows as the gaps
      // widen. Keeping the generator armed is what the header prescribes:
      // "safe to call more than once before the generator receives an event, if
      // events are still imminently possible".
      generator.prepare()
    }

    /// Per-role CoreHaptics character: how hard, how sharp, and how much
    /// sustain sits under the transient.  Sharpness is what keeps roles
    /// distinguishable once intensity is pinned at 1.0 for most of them.
    private func coreProfile(for haptic: AppHaptic) -> (intensity: Float, sharpness: Float, body: TimeInterval)? {
      switch haptic {
      case .selection: (0.85, 0.55, 0.012)
      case .grab: (0.85, 0.20, 0.045)  // dull and swelling — a pickup, not a click
      case .dismiss: (0.90, 0.45, 0.020)
      case .commit: (1.00, 0.70, 0.045)
      case .detent: (1.00, 1.00, 0)  // maximum sharpness, never any sustain
      case .boundary: (1.00, 0.35, 0.075)  // long and dull — a solid wall
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
        // The engine died under us; drop the cache so the next call rebuilds.
        impactPlayers.removeAll()
        return false
      }
    }

    /// Players are cached because building one allocates and crosses into the
    /// haptic server — far too costly to repeat on every tap, let alone on
    /// every detent during a drag.
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
              // Duller than the transient so the sustain reads as weight
              // behind the hit rather than as a second, buzzier event.
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

    /// The weight ladder, quietest to heaviest: soft → light → medium → rigid
    /// → heavy.  Each role sits at its own rung so the roles stay distinguishable
    /// from each other no matter where the baseline puts them.
    private var ladder: [UIImpactFeedbackGenerator] {
      [softGenerator, lightGenerator, mediumGenerator, rigidGenerator, heavyGenerator]
    }

    private func resolve(
      _ haptic: AppHaptic,
      strength: AppHapticStrength
    ) -> (UIImpactFeedbackGenerator, CGFloat) {
      // Rung = character (chosen for feel, not volume).  Trim separates roles
      // that share a rung.  Cap stops a role climbing past where it stops
      // making sense.
      let baseRung: Int
      let trim: CGFloat
      let cap: Int
      switch haptic {
      case .grab:
        baseRung = 0; trim = 1.0; cap = 4  // soft — a swell, not a click
      case .selection:
        baseRung = 1; trim = 0.85; cap = 4  // light, and the lightest thing here
      case .dismiss:
        baseRung = 1; trim = 1.0; cap = 4  // light, but weightier than a plain tap
      case .commit:
        // Capped below `heavy` so `boundary` keeps the top rung to itself:
        // hitting a limit should be the weightiest thing in the app, and
        // without this the two collide at the heaviest baseline.
        baseRung = 2; trim = 1.0; cap = 3  // medium
      case .detent:
        // Capped at rigid on purpose.  Sharpness *is* a tick's identity, and a
        // scrub firing ~15 heavy impacts a second would be unusable — so
        // strength raises a detent's intensity but never its weight.
        //
        // The trim keeps it off `commit`, which lands on rigid too once
        // `heavy` promotes it.  The two never share a context (a mid-drag notch
        // versus a button press), so a small margin is enough to keep them
        // from being literally the same event.
        baseRung = 3; trim = 0.9; cap = 3
      case .boundary:
        baseRung = 4; trim = 1.0; cap = 4  // heavy — a limit must feel unlike a notch
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
        // Must go through `resolve` for the same reason `play` does: warming a
        // generator the current strength will never fire buys nothing.
        resolve(haptic, strength: strength).0.prepare()
      }
    }

    private func playDetent(strength: AppHapticStrength) {
      // A detent is felt by a finger that is already moving and pressed flat to
      // the glass, which masks soft textures badly — hence maximum sharpness on
      // the CoreHaptics path and the sharpest rung on the fallback.
      playImpact(
        .detent,
        strength: strength,
        minimumInterval: Self.detentMinimumInterval(for: strength)
      )
    }

    // MARK: Scene lifecycle

    /// The system tears the CoreHaptics engine down in the background; bring it
    /// back on return so the first celebratory moment after a resume isn't the
    /// one that silently no-ops.
    func wake() {
      // Start eagerly when the baseline renders impacts through CoreHaptics:
      // otherwise the very first tap of a session pays engine start-up latency
      // or silently falls back to the weaker canned generator.
      guard enginePrepared || AppHaptics.strength.usesCoreHapticsImpacts else { return }
      startEngineIfNeeded()
    }

    func sleep() {
      // Players do not survive the engine stopping.
      impactPlayers.removeAll()
      engine?.stop()
    }

    // MARK: CoreHaptics

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
        // Share the app's audio session rather than letting CoreHaptics make
        // its own (which is what `CHHapticEngine()` does).  Per the header,
        // engines sharing a session get "identical audio behavior with regard
        // to interruptions" — in a music app a second, competing session is a
        // real hazard around route changes and interruptions.
        let engine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
        // We never schedule audio events, so keep the engine off audio work
        // entirely.  Must be set before `start()` — the header notes it only
        // takes effect across a stop/restart.
        engine.playsHapticsOnly = true
        // Both handlers can fire while the app is foregrounded — a phone call
        // or another app's audio session will reset us out from under the UI.
        //
        // `@Sendable` is load-bearing, not decoration: with
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor these closures would
        // otherwise inherit @MainActor and trap at runtime when CoreHaptics
        // invokes them off the main queue — the same trap SDWebImage's
        // request modifiers and unguarded Combine sinks hit here before.
        engine.stoppedHandler = { @Sendable [weak self] _ in
          Task { @MainActor in
            self?.impactPlayers.removeAll()
            self?.engine = nil
          }
        }
        engine.resetHandler = { @Sendable [weak self] in
          Task { @MainActor in
            // Players are bound to the engine that built them and do not
            // survive a reset; Apple requires recreating them here.
            self?.impactPlayers.removeAll()
            try? self?.engine?.start()
          }
        }
        try engine.start()
        self.engine = engine
      } catch {
        // A missing engine costs feel, not function: impacts fall back to the
        // canned generators and celebrations to a notification thump.
        impactPlayers.removeAll()
        engine = nil
      }
    }

    /// A two-beat rise: a soft swell that lands on a crisp accent.  Short
    /// enough to punctuate rather than interrupt.
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
      // Ramp the swell upward so the accent reads as its arrival, not a
      // separate second tap.
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
