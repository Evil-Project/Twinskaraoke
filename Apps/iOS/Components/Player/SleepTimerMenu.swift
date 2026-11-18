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
                    audioManager.setSleepTimer(minutes: minutes)
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
                    audioManager.setSleepTimer()
                }
            }
        }
    }
}

struct SleepTimerStatus: View {
    @Environment(AudioPlayerManager.self) private var audioManager
    @Environment(\.locale) private var locale

    var body: some View {
        let timer = audioManager.sleepTimer
        if timer.isActive {
            if let deadline = timer.deadline {
                // The countdown text redraws itself, but the VoiceOver value
                // is read from the body, so tick the body while a deadline
                // runs or VoiceOver reads the time left when it was set.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusMenu(deadline: deadline, now: context.date)
                }
            } else {
                statusMenu(deadline: nil, now: .now)
            }
        }
    }

    private func statusMenu(deadline: Date?, now: Date) -> some View {
        Menu {
            SleepTimerActions()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "moon.zzz")
                if let deadline {
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
        .accessibilityLabel(deadline == nil ? String(localized: "Sleep Timer") : String(localized: "Sleep timer remaining"))
        .accessibilityValue(SleepTimerAccessibility.value(deadline: deadline, now: now, locale: locale))
        .accessibilityIdentifier("SleepTimerStatus")
    }
}
