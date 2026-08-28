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

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var outputVolume: Float { session.outputVolume }

    var currentRoute: AudioRouteDescriptor {
        guard let output = session.currentRoute.outputs.first else { return .unavailable }
        return .resolve(portType: output.portType, name: output.portName)
    }

    func prepareForPlayback() {
        configureCategoryIfNeeded()
        activateIfNeeded()
    }

    func markInterrupted() {
        isActive = false
    }

    func resetAfterMediaServicesLoss() {
        categoryConfigured = false
        isActive = false
        prepareForPlayback()
    }

    private func configureCategoryIfNeeded() {
        guard !categoryConfigured else { return }
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            categoryConfigured = true
        } catch {
            DebugLogger.log(
                "Audio session category configuration failed: \(error)",
                category: .playback
            )
        }
    }

    private func activateIfNeeded() {
        guard !isActive else { return }
        do {
            try session.setActive(true)
            isActive = true
        } catch {
            DebugLogger.log("Audio session activation failed: \(error)", category: .playback)
        }
    }
}
