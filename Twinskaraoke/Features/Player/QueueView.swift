import SwiftUI

struct QueueView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showCurrentAddToPlaylist = false

    private var queueToggleAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)
    }

    private var queueListAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)
    }

    private var queueShuffleAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)
    }

    private var headerAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88)
    }

    private var queueMutationAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
    }

    private var emptyQueueTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var clearButtonTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    var body: some View {
        let upNext = upNextSongs
        ZStack {
            LinearGradient(
                colors: [.appSheetGradientTop, .appSheetGradientBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                header(upNextCount: upNext.count)
                HStack(spacing: 12) {
                    QueueModeButton(
                        symbol: "shuffle",
                        isActive: audioManager.isShuffled,
                        accessibilityLabel: "Shuffle",
                        accessibilityValue: audioManager.isShuffled ? "On" : "Off"
                    ) {
                        audioManager.toggleShuffle()
                    }
                    QueueModeButton(
                        symbol: audioManager.repeatMode.symbol,
                        isActive: audioManager.repeatMode.isActive,
                        accessibilityLabel: "Repeat",
                        accessibilityValue: repeatModeDescription
                    ) {
                        audioManager.toggleRepeat()
                    }
                    QueueModeButton(
                        symbol: "infinity",
                        isActive: audioManager.autoplayEnabled,
                        accessibilityLabel: "Autoplay",
                        accessibilityValue: audioManager.autoplayEnabled ? "On" : "Off"
                    ) {
                        audioManager.toggleAutoplay()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .animation(queueToggleAnimation, value: audioManager.isShuffled)
                .animation(queueToggleAnimation, value: audioManager.repeatMode.isActive)
                .animation(queueToggleAnimation, value: audioManager.autoplayEnabled)
                if let current = audioManager.currentSong {
                    currentSongRow(current)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                }
                if upNext.isEmpty {
                    MusicEmptyState(
                        title: "No songs queued",
                        message: "Songs you play next will appear here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No songs queued")
                    .accessibilityHint("Songs you play next will appear here.")
                    .transition(emptyQueueTransition)
                } else {
                    List {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { index, song in
                            QueueRow(
                                song: song,
                                position: index + 1,
                                isPlayingNext: index == 0,
                                onPlay: {
                                    playQueuedSong(song)
                                },
                                onRemove: {
                                    removeUpNextSong(at: index)
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 14))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeUpNextSong(at: index)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    AppHaptic.selection.play()
                                    audioManager.playNext(song: song)
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.appAccent)
                            }
                            .transition(rowTransition)
                        }
                        .onMove { source, destination in
                            AppHaptic.selection.play()
                            withOptionalAnimation(queueMutationAnimation) {
                                audioManager.moveInUpNext(from: source, to: destination)
                            }
                        }
                        .onDelete { indices in
                            removeUpNextSongs(at: indices)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    .animation(queueShuffleAnimation, value: audioManager.isShuffled)
                    .animation(queueListAnimation, value: upNext.map(\.id))
                }
            }
        }
        .sheet(isPresented: $showCurrentAddToPlaylist) {
            if let current = audioManager.currentSong {
                AddToPlaylistSheet(song: current)
            }
        }
    }

    private func header(upNextCount: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing Next")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(upNextCount == 1 ? "1 song queued" : "\(upNextCount) songs queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Playing Next")
            .accessibilityValue(upNextCount == 1 ? "1 song queued" : "\(upNextCount) songs queued")
            Spacer()
            if upNextCount > 0 {
                Button(role: .destructive) {
                    AppHaptic.warning.play()
                    withOptionalAnimation(queueMutationAnimation) {
                        audioManager.removeFromUpNext(at: IndexSet(integersIn: 0 ..< upNextCount))
                    }
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.appControlInactiveFill, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.93, dim: 0.72))
                .accessibilityLabel("Clear queue")
                .accessibilityValue(upNextCount == 1 ? "1 song queued" : "\(upNextCount) songs queued")
                .accessibilityHint("Removes all songs from Playing Next.")
                .transition(clearButtonTransition)
            }
            GlassXButton(action: {
                AppHaptic.light.play()
                dismiss()
            })
            .accessibilityHint("Dismisses Playing Next.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .animation(headerAnimation, value: upNextCount)
    }

    private func currentSongRow(_ current: Song) -> some View {
        Button {
            AppHaptic.light.play()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RemoteArtworkImage(url: audioManager.displayImageURL(for: current), cornerRadius: 6)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Now Playing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .textCase(.uppercase)
                    Text(current.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(current.displayArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                EqualizerBars(isAnimating: false)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.appAccent)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            SongActionsMenuItems(song: current) {
                showCurrentAddToPlaylist = true
            }
        } preview: {
            SongContextPreview(song: current)
                .environmentObject(audioManager)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now Playing")
        .accessibilityValue("\(current.title), \(current.displayArtist)")
        .accessibilityHint("Double tap to return to the player. More actions are available.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Return to Player") {
            AppHaptic.light.play()
            dismiss()
        }
        .accessibilityAction(named: "Add to Playlist") {
            AppHaptic.selection.play()
            showCurrentAddToPlaylist = true
        }
    }

    private var repeatModeDescription: String {
        switch audioManager.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    private func removeUpNextSong(at index: Int) {
        removeUpNextSongs(at: IndexSet(integer: index))
    }

    private func removeUpNextSongs(at indices: IndexSet) {
        AppHaptic.warning.play()
        withOptionalAnimation(queueMutationAnimation) {
            audioManager.removeFromUpNext(at: indices)
        }
    }

    private func playQueuedSong(_ song: Song) {
        AppHaptic.medium.play()
        audioManager.play(song: song, context: audioManager.queue)
    }

    private var upNextSongs: [Song] {
        guard let current = audioManager.currentSong,
              let idx = audioManager.queue.firstIndex(of: current),
              idx + 1 < audioManager.queue.count
        else { return [] }
        return Array(audioManager.queue[(idx + 1)...])
    }
}

struct QueueRow: View {
    let song: Song
    let position: Int
    let isPlayingNext: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var audioManager: AudioPlayerManager
    @State private var showAddToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        RemoteArtworkImage(url: audioManager.displayImageURL(for: song), cornerRadius: 7)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        if isPlayingNext {
                            Text("NEXT")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.appAccent))
                                .padding(5)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(song.displayArtist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .contextMenu {
                SongActionsMenuItems(song: song) {
                    showAddToPlaylist = true
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "text.badge.minus")
                }
            } preview: {
                SongContextPreview(song: song)
                    .environmentObject(audioManager)
            }
            .accessibilityLabel("\(position). \(song.title), \(song.displayArtist)")
            .accessibilityValue(isPlayingNext ? "Playing next" : "Queued")
            .accessibilityHint("Plays this song from the queue.")
            Menu {
                SongActionsMenuItems(song: song) {
                    showAddToPlaylist = true
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "text.badge.minus")
                }
            } label: {
                Label("More actions", systemImage: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
            .accessibilityLabel("More actions")
            .accessibilityHint("Shows actions for \(song.title).")
        }
        .padding(.vertical, 3)
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .accessibilityAction(named: "Play") {
            onPlay()
        }
        .accessibilityAction(named: "Add to Playlist") {
            AppHaptic.selection.play()
            showAddToPlaylist = true
        }
        .accessibilityAction(named: "Remove from Queue") {
            onRemove()
        }
    }
}

struct QueueModeButton: View {
    let symbol: String
    let isActive: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let action: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if #available(iOS 17.0, *), !reduceMotion {
                    Image(systemName: symbol)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(isActive ? Color.appControlActiveForeground : .primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .modifier(QueueModeBackground(isActive: isActive))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.75, haptic: .selection))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double tap to toggle.")
    }

}

private struct QueueModeBackground: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isActive {
                content.background(Capsule().fill(Color.appControlActiveFill))
            } else {
                content.glassEffect(in: Capsule())
            }
        } else {
            content.background(
                Capsule()
                    .fill(isActive ? Color.appControlActiveFill : Color.appControlInactiveFill)
            )
        }
    }
}
