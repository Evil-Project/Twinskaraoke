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
            // A live station has no end to wait for.
            if !audioManager.isRadioMode {
                Button("When Current Song Ends") {
                    audioManager.startSleepTimerAtEndOfSong()
                }
            }
            if audioManager.sleepTimer.isActive {
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
        let timer = audioManager.sleepTimer
        if timer.isActive {
            Menu {
                SleepTimerActions()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz")
                    if let deadline = timer.deadline {
                        Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true)
                            .monospacedDigit()
                    } else {
                        Text("End of Song")
                    }
                }
                .font(.caption)
                .padding(8)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
            }
            .accessibilityLabel(timer.deadline == nil ? String(localized: "Sleep Timer") : String(localized: "Sleep timer remaining"))
            .accessibilityValue(timer.deadline == nil ? String(localized: "End of Song") : "")
            .accessibilityIdentifier("SleepTimerStatus")
        }
    }
}
