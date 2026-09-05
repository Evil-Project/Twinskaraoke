import SwiftUI

struct SleepTimerMenu: View {
    var body: some View {
        Menu {
            SleepTimerActions()
        } label: {
            Label("Sleep Timer", systemImage: "moon.zzz")
        }
        .accessibilityIdentifier("SleepTimerMenu")
    }
}

private struct SleepTimerActions: View {
    @Environment(AudioPlayerManager.self) private var audioManager

    var body: some View {
        Group {
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
        }
    }
}

struct SleepTimerStatus: View {
    @Environment(AudioPlayerManager.self) private var audioManager

    var body: some View {
        if let deadline = audioManager.sleepTimer.deadline {
            Menu {
                SleepTimerActions()
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
