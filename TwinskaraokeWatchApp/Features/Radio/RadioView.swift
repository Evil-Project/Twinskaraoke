import SwiftUI

struct RadioView: View {
    @ObservedObject private var radio = RadioController.shared
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var playbackAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    /// The station is only "on" while this app is the one streaming it.
    private var isTunedIn: Bool {
        audioManager.isRadioMode
    }

    var body: some View {
        List {
            if let metadata = radio.nowPlaying {
                Section {
                    RadioNowPlayingCard(
                        station: metadata.station,
                        song: metadata.nowPlaying?.song,
                        listeners: metadata.listeners,
                        isTunedIn: isTunedIn,
                        isBuffering: isTunedIn && audioManager.isLoading
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)

                    Button {
                        toggleListening()
                    } label: {
                        Label(
                            isTunedIn ? "Stop" : "Listen Live",
                            systemImage: isTunedIn ? "stop.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.watchPressable)
                    .accessibilityIdentifier("WatchRadio.listen")
                    .accessibilityLabel(isTunedIn ? "Stop" : "Listen Live")
                    .accessibilityHint(
                        isTunedIn
                            ? "Stops the live station."
                            : "Starts playing the live station."
                    )
                }

                if let next = metadata.playingNext?.song {
                    Section("Up Next") {
                        RadioTrackRow(song: next)
                    }
                }

                if let history = metadata.songHistory, !history.isEmpty {
                    Section("Just Played") {
                        ForEach(Array(history.prefix(3).enumerated()), id: \.offset) { _, item in
                            RadioTrackRow(song: item.song)
                        }
                    }
                }
            } else if let error = radio.refreshErrorMessage {
                WatchLoadErrorState(
                    title: "Radio Unavailable",
                    message: error,
                    retryAction: { Task { await radio.refresh() } }
                )
                .listRowBackground(Color.clear)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle("Radio")
        .animation(playbackAnimation, value: isTunedIn)
        .animation(playbackAnimation, value: audioManager.isLoading)
        .onAppear {
            radio.start()
        }
        .onDisappear {
            // `stop` keeps polling alive if the station is still streaming —
            // the Now Playing card outlives this view — and retires it once
            // playback ends.
            radio.stop()
            WatchArtworkPrefetcher.shared.cancel(reason: "radio")
        }
    }

    private func toggleListening() {
        if isTunedIn {
            audioManager.stopRadio()
            WatchHaptic.play(.stop)
        } else {
            radio.playLiveStream()
            WatchHaptic.play(.start)
        }
    }
}

private struct RadioNowPlayingCard: View {
    let station: RadioNowPlaying.Station
    let song: RadioNowPlaying.SongInfo?
    let listeners: RadioNowPlaying.Listeners?
    let isTunedIn: Bool
    let isBuffering: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    WatchCachedImage(url: artURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.appAccent.opacity(0.16))
                            .overlay {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.appAccent)
                            }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if isBuffering {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 44, height: 44)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isTunedIn ? .appAccent : .primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                RadioStatusPill(
                    systemImage: isTunedIn ? "waveform" : "dot.radiowaves.left.and.right",
                    title: isTunedIn ? "Live" : station.name
                )
                if let listeners {
                    RadioStatusPill(
                        systemImage: "person.2.fill",
                        title: "\(listeners.total)"
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isTunedIn ? "Playing live" : "Live radio")
        .accessibilityValue(accessibilityValue)
    }

    private var artURL: URL? {
        song?.art.flatMap { URL(string: $0) }
    }

    private var title: String {
        song?.title ?? song?.text ?? station.name
    }

    private var subtitle: String? {
        song?.artist ?? station.description
    }

    private var accessibilityValue: String {
        [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct RadioStatusPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundColor(.appAccent)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(
                Capsule().fill(Color.appAccent.opacity(0.12))
            )
    }
}

/// Metadata-only row: the station decides what plays, so these are not
/// tappable the way a library song is.
private struct RadioTrackRow: View {
    let song: RadioNowPlaying.SongInfo

    var body: some View {
        HStack(spacing: 10) {
            WatchCachedImage(url: song.art.flatMap { URL(string: $0) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.16))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? song.text ?? "Unknown")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title ?? song.text ?? "Unknown")
        .accessibilityValue(song.artist ?? "")
    }
}
