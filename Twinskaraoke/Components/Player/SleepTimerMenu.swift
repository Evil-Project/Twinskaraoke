import SwiftUI

struct SleepTimerMenu: View {
    @Environment(AudioPlayerManager.self) private var audioManager

    var body: some View {
        Menu {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    audioManager.sleepTimer.start(minutes: minutes)
                }
            }
            if audioManager.sleepTimer.deadline != nil {
                Button("Cancel Sleep Timer", role: .destructive) {
                    audioManager.sleepTimer.cancel()
                }
            }
        } label: {
            Label("Sleep Timer", systemImage: "moon.zzz")
        }
        .accessibilityIdentifier("SleepTimerMenu")
    }
}

struct SleepTimerStatus: View {
    @Environment(AudioPlayerManager.self) private var audioManager

    var body: some View {
        if let deadline = audioManager.sleepTimer.deadline {
            Menu {
                SleepTimerMenu()
                Button("Cancel Sleep Timer", role: .destructive) {
                    audioManager.sleepTimer.cancel()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz")
                    Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(8)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Sleep timer remaining")
            .accessibilityIdentifier("SleepTimerStatus")
        }
    }
}
