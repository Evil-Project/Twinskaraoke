import AVFoundation
import Foundation

nonisolated struct AudioRouteDescriptor: Equatable, Sendable {
    let name: String
    let symbol: String

    static let unavailable = AudioRouteDescriptor(name: "", symbol: "airplayaudio")

    static func resolve(portType: AVAudioSession.Port, name: String) -> AudioRouteDescriptor {
        let normalizedName = name.lowercased()
        let symbol: String
        switch portType {
        case .builtInSpeaker, .builtInReceiver:
            symbol = "airplayaudio"
        case .headphones:
            symbol = "headphones"
        case .HDMI:
            symbol = "tv.fill"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            if normalizedName.contains("airpods max") {
                symbol = "airpodsmax"
            } else if normalizedName.contains("airpods pro") {
                symbol = "airpodspro"
            } else if normalizedName.contains("airpods") {
                symbol = "airpods"
            } else if normalizedName.contains("beats") {
                symbol = "beats.headphones"
            } else {
                symbol = "hifispeaker.fill"
            }
        case .airPlay:
            if normalizedName.contains("homepod mini") {
                symbol = "homepodmini"
            } else if normalizedName.contains("homepod") {
                symbol = "homepod"
            } else if normalizedName.contains("apple tv") {
                symbol = "appletv"
            } else {
                symbol = "airplayaudio"
            }
        default:
            symbol = "airplayaudio"
        }
        return AudioRouteDescriptor(name: name, symbol: symbol)
    }
}

@MainActor
protocol AudioSessionManaging: AnyObject {
    var outputVolume: Float { get }
    var currentRoute: AudioRouteDescriptor { get }

    var hasPendingPlayback: Bool { get }
    func performWhenReady(_ operation: @escaping @MainActor () -> Void, replacingPending: Bool) -> Bool
    func cancelPendingPlayback()
    func prepareForPlayback()
    func markInterrupted()
    func resetAfterMediaServicesLoss()
}

/// Owns the process-wide AVAudioSession configuration state.
///
/// Playback code can ask for a prepared session without duplicating the
/// category/activation guards or reaching into AVAudioSession directly.
@MainActor
final class AudioSessionController: AudioSessionManaging {
    private let session: AVAudioSession
    private var categoryConfigured = false
    private var isActive = false
    private var isActivating = false
    private var activationGeneration = 0
    private var pendingActivationWasCancelled = false
    private var pendingPlayback: (@MainActor () -> Void)?
    private let configure: @MainActor () throws -> Void
    private let activate: @MainActor (@escaping @Sendable (Bool, (any Error)?) -> Void) -> Void

    var hasPendingPlayback: Bool { pendingPlayback != nil }

    /// Only the latest request survives activation; Pause can cancel it.
    func performWhenReady(_ operation: @escaping @MainActor () -> Void, replacingPending: Bool = true) -> Bool {
        if isActive { return true }
        if replacingPending {
            pendingActivationWasCancelled = false
        } else if pendingActivationWasCancelled {
            // A late file/stem preparation must not undo Pause while the
            // activation callback is still in flight. Only a new Play can.
            return false
        }
        if replacingPending || pendingPlayback == nil { pendingPlayback = operation }
        prepareForPlayback()
        return false
    }

    func cancelPendingPlayback() {
        if isActivating { pendingActivationWasCancelled = true }
        pendingPlayback = nil
    }

    init(
        session: AVAudioSession = .sharedInstance(),
        configure: (@MainActor () throws -> Void)? = nil,
        activate: (@MainActor (@escaping @Sendable (Bool, (any Error)?) -> Void) -> Void)? = nil
    ) {
        self.session = session
        self.configure = configure ?? {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        }
        self.activate = activate ?? { completion in
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                session.activate(options: [], completionHandler: completion)
                return
            }
            #endif
            // Older SDKs cannot name the iOS async API, including when their
            // binary runs on iOS 27. Never block the main actor in that fallback.
            Self.activateInBackground({ try session.setActive(true) }, completion: completion)
        }
    }

    private nonisolated static let activationQueue = DispatchQueue(
        label: "Twinskaraoke.audio-session.activation", qos: .userInitiated
    )

    /// Serialize synchronous activation attempts without blocking UI work.
    /// Completion is delivered off-main; activateIfNeeded restores actor isolation.
    nonisolated static func activateInBackground(
        _ operation: @escaping @Sendable () throws -> Void,
        completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        activationQueue.async {
            do {
                try operation()
                completion(true, nil)
            } catch { completion(false, error) }
        }
    }

    var outputVolume: Float { session.outputVolume }

    var currentRoute: AudioRouteDescriptor {
        guard let output = session.currentRoute.outputs.first else { return .unavailable }
        return .resolve(portType: output.portType, name: output.portName)
    }

    func prepareForPlayback() {
        guard configureCategoryIfNeeded() else { pendingPlayback = nil; return }
        activateIfNeeded()
    }

    func markInterrupted() {
        activationGeneration &+= 1
        isActivating = false
        isActive = false
        cancelPendingPlayback()
    }

    func resetAfterMediaServicesLoss() {
        markInterrupted()
        categoryConfigured = false
    }

    private func configureCategoryIfNeeded() -> Bool {
        guard !categoryConfigured else { return true }
        do {
            try configure()
            categoryConfigured = true
            return true
        } catch {
            DebugLogger.log(
                "Audio session category configuration failed: \(error)",
                category: .playback
            )
            return false
        }
    }

    private func activateIfNeeded() {
        guard !isActive, !isActivating else { return }
        isActivating = true
        let generation = activationGeneration
        activate { [weak self] activated, error in
            Task { @MainActor [weak self] in
                guard let self, self.activationGeneration == generation else { return }
                self.isActivating = false
                self.isActive = activated && error == nil
                let playback = self.pendingPlayback
                self.pendingPlayback = nil
                guard self.isActive else {
                    DebugLogger.log("Audio session activation failed: \(String(describing: error))", category: .playback)
                    return
                }
                playback?()
            }
        }
    }
}
