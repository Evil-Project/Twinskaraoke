import SwiftUI

struct QueueView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showCurrentAddToPlaylist = false

    private var queueToggleAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var headerAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var queueMutationAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
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
                        ForEach(Array(upNext.enumerated()), id: \.offset) { index, song in
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
                    .contentTransition(.numericText())
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
                RemoteArtworkImage(
                    url: audioManager.displayImageURL(for: current, variant: .row),
                    cornerRadius: 6,
                    lowResURL: current.thumbnailURL
                )
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

                EqualizerBars(isAnimating: audioManager.isPlaying)
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
        // Match by id: applyEnrichedMetadata replaces currentSong with a fresh
        // instance that no longer == the queue copy.
        guard let current = audioManager.currentSong,
              let idx = audioManager.queue.firstIndex(where: { $0.id == current.id }),
              idx + 1 < audioManager.queue.count
        else { return [] }
        return Array(audioManager.queue[(idx + 1)...])
    }
}
