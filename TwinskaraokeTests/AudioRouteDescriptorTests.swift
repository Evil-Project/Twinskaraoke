import AVFoundation
import Testing
@testable import Twinskaraoke

@Suite("Audio route presentation")
struct AudioRouteDescriptorTests {
    @Test("Known Apple audio routes use specific system symbols", arguments: [
        (AVAudioSession.Port.bluetoothA2DP, "AirPods Pro", "airpodspro"),
        (AVAudioSession.Port.bluetoothA2DP, "AirPods Max", "airpodsmax"),
        (AVAudioSession.Port.bluetoothLE, "Beats Studio", "beats.headphones"),
        (AVAudioSession.Port.airPlay, "Living Room Apple TV", "appletv"),
        (AVAudioSession.Port.airPlay, "Kitchen HomePod mini", "homepodmini"),
        (AVAudioSession.Port.HDMI, "Receiver", "tv.fill"),
    ])
    func systemSymbol(port: AVAudioSession.Port, name: String, expected: String) {
        let descriptor = AudioRouteDescriptor.resolve(portType: port, name: name)
        #expect(descriptor.name == name)
        #expect(descriptor.symbol == expected)
    }

    @Test("Unknown Bluetooth devices use a stable speaker fallback")
    func genericBluetoothFallback() {
        let descriptor = AudioRouteDescriptor.resolve(
            portType: .bluetoothA2DP,
            name: "Conference Speaker"
        )
        #expect(descriptor.symbol == "hifispeaker.fill")
    }
}
