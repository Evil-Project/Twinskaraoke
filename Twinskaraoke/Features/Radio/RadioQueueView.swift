import SwiftUI

struct RadioQueueView: View {
    @ObservedObject var radio = RadioController.shared
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion

    private var currentSong: RadioNowPlaying.SongInfo? {
        radio.nowPlaying?.nowPlaying?.song
    }

    private var nextSong: RadioNowPlaying.SongInfo? {
        radio.nowPlaying?.playingNext?.song
    }

    private var history: [RadioNowPlaying.HistoryItem] {
        Array((radio.nowPlaying?.songHistory ?? []).prefix(20))
    }

    private var hasSchedule: Bool {
        currentSong != nil || nextSong != nil || !history.isEmpty
    }

    private var isLivePlaying: Bool {
        audioManager.isRadioMode && audioManager.isPlaying
    }

    private var isOnLiveStation: Bool {
        audioManager.isRadioMode && audioManager.currentSong != nil
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.appSheetGradientTop, .appSheetGradientBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let current = currentSong {
                            RadioQueueHero(
                                song: current,
                                stationName: radio.nowPlaying?.station.name ?? "Twinskaraoke Radio",
                                listenerCount: radio.nowPlaying?.listeners?.unique,
                                lastUpdated: radio.lastUpdated,
                                isPlaying: isLivePlaying,
                                reduceMotion: reduceMotion
                            ) {
                                playOrPauseLiveStation()
                            }
                            .transition(heroTransition)
                        }
                        stationControls
                        if let next = nextSong {
                            section(title: "Up Next") {
                                row(song: next, isCurrent: false)
                            }
                        }
                        if !history.isEmpty {
                            section(title: "Recently Played") {
                                VStack(spacing: 0) {
                                    ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                                        row(song: item.song, isCurrent: false)
                                        Rectangle()
                                            .fill(Color.appDivider)
                                            .frame(height: 0.5)
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                        }
                        if !hasSchedule {
                            MusicEmptyState(
                                title: "Radio Schedule Unavailable",
                                message: "Pull down to refresh live station metadata."
                            )
                            .padding(.top, 36)
                            .transition(emptyStateTransition)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .animation(scheduleAnimation(response: 0.28), value: currentSong?.displayTitle)
                    .animation(scheduleAnimation(response: 0.24), value: history.count)
                }
                .smoothScrolling()
                .refreshable { await radio.refresh() }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(radio.nowPlaying?.station.name ?? "Radio")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let listeners = radio.nowPlaying?.listeners {
                    Text("\(listeners.unique) listening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            GlassXButton(action: {
                AppHaptic.light.play()
                dismiss()
            })
            .accessibilityHint("Dismisses the radio queue.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var stationControls: some View {
        HStack(spacing: 12) {
            Button {
                AppHaptic.medium.play()
                playOrPauseLiveStation()
            } label: {
                LibraryActionButtonLabel(
                    symbol: isLivePlaying ? "pause.fill" : "play.fill",
                    text: isLivePlaying ? "Pause Live" : "Play Live"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel(isLivePlaying ? "Pause live station" : "Play live station")
            .accessibilityValue(radio.nowPlaying?.station.name ?? "Twinskaraoke Radio")
            .accessibilityHint("Controls the live radio stream.")

            Button {
                AppHaptic.selection.play()
                Task { await radio.refresh() }
            } label: {
                LibraryActionButtonLabel(symbol: "arrow.clockwise", text: "Refresh")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Refresh radio metadata")
            .accessibilityHint("Updates live now, up next, and recently played.")
        }
        .transition(stationControlsTransition)
    }

    private func playOrPauseLiveStation() {
        if isOnLiveStation {
            audioManager.togglePlayPause()
        } else {
            radio.playLiveStream()
        }
    }

    private func section(title: String, @ViewBuilder content: () -> some View)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func row(song: RadioNowPlaying.SongInfo, isCurrent: Bool) -> some View {
        RadioQueueTrackRow(
            song: song,
            isCurrent: isCurrent,
            isPlaying: isCurrent && isLivePlaying
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                AppHaptic.medium.play()
                radio.playLiveStream()
            } label: {
                Label("Play Live Station", systemImage: "dot.radiowaves.left.and.right")
            }

            Button {
                AppHaptic.selection.play()
                Task { await radio.refresh() }
            } label: {
                Label("Refresh Metadata", systemImage: "arrow.clockwise")
            }
        } preview: {
            RadioQueuePreview(song: song, isCurrent: isCurrent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isCurrent ? "Live now" : "Radio track")
        .accessibilityValue("\(song.displayTitle), \(song.displayArtist)")
        .accessibilityHint("Shows actions for the live radio station.")
        .accessibilityAction(named: "Play Live Station") {
            AppHaptic.medium.play()
            radio.playLiveStream()
        }
        .transition(rowTransition)
    }

    private func scheduleAnimation(response: Double) -> Animation? {
        reduceMotion ? nil : AppMotion.spring(response: response, dampingFraction: 0.84)
    }


    private var heroTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var emptyStateTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    private var stationControlsTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }
}
