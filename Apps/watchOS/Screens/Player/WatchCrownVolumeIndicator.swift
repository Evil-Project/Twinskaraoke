import AVFAudio
import Combine
import SwiftUI
import WatchKit

/// Read the Watch's output volume without taking Crown focus away from WatchKit.
struct WatchCrownVolumeIndicator: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var level: Float?

    static var alignment: Alignment {
        WKInterfaceDevice.current().crownOrientation == .left ? .leading : .trailing
    }

    var body: some View {
        Color.clear
            .frame(width: 5, height: 44)
            .overlay {
                if let level {
                    Capsule()
                        .fill(.secondary.opacity(0.4))
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(Color.appAccent)
                                .frame(height: 44 * CGFloat(level))
                        }
                }
            }
            .padding(.horizontal, 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onReceive(
                AVAudioSession.sharedInstance().publisher(for: \.outputVolume, options: [.new])
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
            ) { volume in
                guard scenePhase == .active, volume.isFinite else { return }
                level = min(max(volume, 0), 1)
            }
            .task(id: level) {
                guard level != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(1.5))
                    level = nil
                } catch {}
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { level = nil }
            }
    }
}
