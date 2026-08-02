import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showCurrentAddToPlaylist = false
    @State private var upNextEntries: [UpNextEntry] = []

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
        let upNext = upNextEntries
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
                        ForEach(upNext) { entry in
                            QueueRow(
                                song: entry.song,
                                position: entry.position,
                                isPlayingNext: entry.position == 1,
                                onPlay: {
                                    playQueuedSong(entry.song)
                                },
                                onRemove: {
                                    removeUpNextSong(at: entry.position - 1)
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 14))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeUpNextSong(at: entry.position - 1)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    AppHaptic.selection.play()
                                    audioManager.playNext(song: entry.song)
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
        // Snapshot up-next only when the queue or current song changes, so
        // unrelated AudioPlayerManager publishes don't redo the O(n) slice.
        .onAppear { refreshUpNextSongs() }
        .onChange(of: audioManager.queue) { _, _ in refreshUpNextSongs() }
        .onChange(of: audioManager.currentSong?.id) { _, _ in refreshUpNextSongs() }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "queue up next")
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
                .environment(audioManager)
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

    private func refreshUpNextSongs() {
        // Match by id: applyEnrichedMetadata replaces currentSong with a fresh
        // instance that no longer == the queue copy.
        guard let current = audioManager.currentSong,
              let idx = audioManager.queue.firstIndex(where: { $0.id == current.id }),
              idx + 1 < audioManager.queue.count
        else {
            ArtworkPrefetcher.shared.cancel(reason: "queue up next")
            upNextEntries = []
            return
        }
        let songs = Array(audioManager.queue[(idx + 1)...])
        // Stable identities across refreshes: match each occurrence to the
        // previous entry with the same (song id, occurrence index) pair, so
        // identity follows the song occurrence rather than the position — a
        // moved row keeps its UUID, and minting fresh UUIDs here would destroy
        // every row (killing sheets/drags) on each track advance.
        var previousIDs: [String: UUID] = [:]
        var previousCounts: [String: Int] = [:]
        for entry in upNextEntries {
            let occurrence = previousCounts[entry.song.id, default: 0]
            previousCounts[entry.song.id] = occurrence + 1
            previousIDs["\(entry.song.id)#\(occurrence)"] = entry.id
        }
        var newCounts: [String: Int] = [:]
        upNextEntries = songs.enumerated().map { offset, song in
            let occurrence = newCounts[song.id, default: 0]
            newCounts[song.id] = occurrence + 1
            let id = previousIDs["\(song.id)#\(occurrence)"] ?? UUID()
            return UpNextEntry(id: id, song: song, position: offset + 1)
        }
        // Rows otherwise rely on the source list having warmed these; the queue
        // can outlive that list, so warm the row variants here too.
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(songs.prefix(12)),
            limit: 12,
            reason: "queue up next",
            variant: .row
        )
    }
}

/// Stable identity for a queue row: positional `ForEach` identity mis-tracks
/// rows while the user reorders the up-next list, so each queue occurrence
/// gets a UUID that refreshUpNextSongs carries across refreshes.
private struct UpNextEntry: Identifiable {
    let id: UUID
    let song: Song
    /// 1-based display position; also the index into the up-next slice + 1.
    let position: Int
}
