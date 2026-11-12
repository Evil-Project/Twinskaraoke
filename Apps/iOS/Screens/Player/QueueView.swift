import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showCurrentAddToPlaylist = false
    @State private var upNextEntries: [UpNextEntry] = []
    @State private var isReordering = false

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
                // One container renders the capsules together; matching the
                // stack's spacing keeps them apart at rest (Apple's guidance).
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        QueueModeButton(
                            symbol: "shuffle",
                            isActive: audioManager.isShuffled,
                            accessibilityLabel: String(localized: "Shuffle"),
                            accessibilityValue: audioManager.isShuffled ? String(localized: "On") : String(localized: "Off")
                        ) {
                            audioManager.toggleShuffle()
                        }
                        QueueModeButton(
                            symbol: audioManager.repeatMode.symbol,
                            isActive: audioManager.repeatMode.isActive,
                            accessibilityLabel: String(localized: "Repeat"),
                            accessibilityValue: repeatModeDescription
                        ) {
                            audioManager.toggleRepeat()
                        }
                        QueueModeButton(
                            symbol: "infinity",
                            isActive: audioManager.autoplayEnabled,
                            accessibilityLabel: String(localized: "Autoplay"),
                            accessibilityValue: audioManager.autoplayEnabled ? String(localized: "On") : String(localized: "Off")
                        ) {
                            audioManager.toggleAutoplay()
                        }
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
                        title: String(localized: "No songs queued"),
                        message: String(localized: "Songs you play next will appear here.")
                    )
                    .scrollsWhenTooTall()
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
                                    playQueuedSong(entry)
                                },
                                onRemove: {
                                    removeUpNextSongs(ids: [entry.id])
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 14))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeUpNextSongs(ids: [entry.id])
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    AppHaptic.commit.play()
                                    audioManager.playNext(song: entry.song)
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.appAccent)
                            }
                            .transition(rowTransition)
                        }
                        .onMove { source, destination in
                            guard upNext.map(\.id) == audioManager.upNextEntries.map(\.id) else { return }
                            AppHaptic.commit.play()
                            withOptionalAnimation(queueMutationAnimation) {
                                audioManager.moveInUpNext(from: source, to: destination)
                            }
                        }
                        .onDelete { indices in
                            removeUpNextSongs(ids: Set(indices.compactMap { upNext.indices.contains($0) ? upNext[$0].id : nil }))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .smoothScrolling()
                    .accessibilityIdentifier("Queue.List")
                    .environment(\.editMode, .constant(isReordering ? .active : .inactive))
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
        .onChange(of: audioManager.upNextEntries) { _, _ in refreshUpNextSongs() }
        .onChange(of: upNextEntries.isEmpty) { _, isEmpty in
            if isEmpty { isReordering = false }
        }
        .onDisappear {
            ArtworkPrefetcher.shared.cancel(reason: "queue up next")
        }
    }

    private func header(upNextCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Playing Next")
                    .font(AM.Font.groupHeader)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                GlassXButton(action: {
                    AppHaptic.dismiss.play()
                    dismiss()
                })
                .accessibilityHint("Dismisses Playing Next.")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    queueCount(upNextCount).fixedSize()
                    Spacer(minLength: 8)
                    queueActions(upNextCount).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    queueCount(upNextCount)
                    queueActions(upNextCount)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .animation(headerAnimation, value: upNextCount)
    }

    private func queueCount(_ count: Int) -> some View {
        Text(count == 1 ? "1 song queued" : "\(count) songs queued")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func queueActions(_ upNextCount: Int) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if upNextCount > 1 || isReordering {
                    Button {
                        AppHaptic.selection.play()
                        withOptionalAnimation(queueMutationAnimation) {
                            isReordering.toggle()
                        }
                    } label: {
                        Text(isReordering ? "Done" : "Reorder")
                            .font(AM.Font.rowCompactTitle.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .appGlassBackground(in: Capsule(), fallback: .appControlInactiveFill)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("Queue.Reorder")
                    .accessibilityHint(isReordering ? "Finishes rearranging the queue." : "Shows handles to rearrange upcoming songs.")
                }
                if upNextCount > 0 {
                    Button(role: .destructive) {
                        AppHaptic.dismiss.play()
                        withOptionalAnimation(queueMutationAnimation) {
                            audioManager.removeFromUpNext(at: IndexSet(integersIn: 0 ..< upNextCount))
                        }
                    } label: {
                        Text("Clear")
                            .font(AM.Font.rowCompactTitle.weight(.semibold))
                            .foregroundStyle(Color.appDestructive)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 44)
                            .appGlassBackground(in: Capsule(), fallback: .appControlInactiveFill)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.93, dim: 0.72))
                    .accessibilityLabel("Clear queue")
                    .accessibilityValue(upNextCount == 1 ? "1 song queued" : "\(upNextCount) songs queued")
                    .accessibilityHint("Removes all songs from Playing Next.")
                    .transition(clearButtonTransition)
                }
            }
        }
    }

    private func currentSongRow(_ current: Song) -> some View {
        Button {
            AppHaptic.selection.play()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RemoteArtworkImage(
                    url: audioManager.displayImageURL(for: current, variant: .row),
                    cornerRadius: AM.Radius.thumb,
                    lowResURL: current.thumbnailURL
                )
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Now Playing")
                        .font(AM.Font.badge)
                        .foregroundStyle(Color.appAccent)
                        .textCase(.uppercase)
                    Text(current.title)
                        .font(AM.Font.groupHeader)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(current.displayArtist)
                        .font(AM.Font.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                EqualizerBars(isAnimating: audioManager.isPlaying, pausesWhileScrolling: false)
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
            AppHaptic.selection.play()
            dismiss()
        }
        .accessibilityAction(named: "Add to Playlist") {
            AppHaptic.selection.play()
            showCurrentAddToPlaylist = true
        }
    }

    private var repeatModeDescription: String {
        switch audioManager.repeatMode {
        case .off: String(localized: "Don't Repeat")
        case .all: String(localized: "Repeat")
        case .one: String(localized: "Repeat Once")
        }
    }

    private func removeUpNextSongs(ids: Set<UUID>) {
        AppHaptic.dismiss.play()
        withOptionalAnimation(queueMutationAnimation) {
            audioManager.removeFromUpNext(ids: ids)
        }
    }

    private func playQueuedSong(_ entry: UpNextEntry) {
        AppHaptic.commit.play()
        audioManager.skipToQueuedEntry(.init(id: entry.id, song: entry.song))
    }

    private func refreshUpNextSongs() {
        let entries = audioManager.upNextEntries
        guard !entries.isEmpty else {
            ArtworkPrefetcher.shared.cancel(reason: "queue up next")
            upNextEntries = []
            return
        }
        upNextEntries = entries.enumerated().map { offset, entry in
            UpNextEntry(id: entry.id, song: entry.song, position: offset + 1)
        }
        let songs = entries.map(\.song)
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
