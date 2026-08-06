import SwiftUI

struct AddToPlaylistSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    private let manager = UserPlaylistsManager.shared

    @State private var inFlight: Set<String> = []
    @State private var added: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var showCreatePlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    AddToPlaylistSongPreview(song: song)
                        .padding(.top, 8)

                    if manager.isLoading, manager.playlists.isEmpty {
                        AddToPlaylistLoadingRows()
                            .transition(.opacity)
                    } else if manager.playlists.isEmpty {
                        emptyState
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(manager.playlists) { playlist in
                                Button {
                                    add(to: playlist)
                                } label: {
                                    AddToPlaylistRow(
                                        playlist: playlist,
                                        state: state(for: playlist)
                                    )
                                }
                                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82, haptic: rowHaptic(for: playlist)))
                                .disabled(inFlight.contains(playlist.id) || added.contains(playlist.id))
                                .contextMenu {
                                    Button {
                                        add(to: playlist)
                                    } label: {
                                        Label("Add to Playlist", systemImage: "plus.circle")
                                    }
                                    Button {
                                        AppHaptic.selection.play()
                                        showCreatePlaylist = true
                                    } label: {
                                        Label("New Playlist", systemImage: "music.note.list")
                                    }
                                } preview: {
                                    AddToPlaylistPreview(playlist: playlist)
                                }
                            }
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .smoothScrolling()
            .musicScreenBackground()
            // `safeAreaBar`, not `safeAreaInset`: this is a bar, so the system
            // supplies its background and scroll-edge behaviour. That replaces
            // the hand-applied glass this used to carry, which never sat right
            // — glass suits a floating shape, and this is flush and full-width.
            .safeAreaBar(edge: .bottom) {
                if !manager.playlists.isEmpty {
                    Button {
                        AppHaptic.commit.play()
                        showCreatePlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(Color.appControlActiveForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appControlActiveFill, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.78, haptic: nil))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // These carry their own glass, so the toolbar must not put its
                // shared glass behind them as well.
                ToolbarItem(placement: .cancellationAction) {
                    GlassXButton(action: {
                        AppHaptic.selection.play()
                        dismiss()
                    })
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    GlassCheckmarkButton(
                        action: {
                            AppHaptic.selection.play()
                            dismiss()
                        },
                        isEnabled: !added.isEmpty
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .task { manager.loadIfNeeded() }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistSheet()
            }
            .animation(reduceMotion ? nil : AppMotion.snap, value: inFlight)
            .animation(reduceMotion ? nil : AppMotion.quick, value: added)
            .animation(reduceMotion ? nil : AppMotion.snap, value: failed)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            MusicEmptyState(
                title: "No Playlists",
                message: "Create a playlist first to save this song."
            )
            Button {
                AppHaptic.commit.play()
                showCreatePlaylist = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Color.appControlActiveForeground)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.appControlActiveFill, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.95, dim: 0.78, haptic: nil))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func state(for playlist: UserPlaylist) -> AddToPlaylistRowState {
        if inFlight.contains(playlist.id) { return .adding }
        if added.contains(playlist.id) { return .added }
        if failed.contains(playlist.id) { return .failed }
        return .idle
    }

    private func rowHaptic(for playlist: UserPlaylist) -> AppHaptic? {
        added.contains(playlist.id) || inFlight.contains(playlist.id) ? nil : .selection
    }

    private func add(to playlist: UserPlaylist) {
        guard !inFlight.contains(playlist.id), !added.contains(playlist.id) else { return }
        inFlight.insert(playlist.id)
        failed.remove(playlist.id)
        manager.addSong(song.id, toPlaylist: playlist.id) { success in
            inFlight.remove(playlist.id)
            if success {
                AppHaptic.success.play()
                added.insert(playlist.id)
            } else {
                AppHaptic.error.play()
                failed.insert(playlist.id)
            }
        }
    }
}

private enum AddToPlaylistRowState: Hashable {
    case idle
    case adding
    case added
    case failed
}

private struct AddToPlaylistSongPreview: View {
    let song: Song

    var body: some View {
        HStack(spacing: 14) {
            RemoteArtworkImage(url: song.thumbnailURL ?? song.imageURL, cornerRadius: 10)
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.appShadow, radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("Add Song")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AddToPlaylistRow: View {
    let playlist: UserPlaylist
    let state: AddToPlaylistRowState

    var body: some View {
        HStack(spacing: 12) {
            PlaylistArtwork(playlist: playlist.asPlaylist(), cornerRadius: 7)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            statusView
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: state == .idle ? 0 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitle: String {
        switch state {
        case .idle:
            SongCountText.songs(playlist.songCount)
        case .adding:
            "Adding..."
        case .added:
            "Added"
        case .failed:
            "Could not add. Tap to retry."
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            Image(systemName: "plus.circle")
                .font(.title3.bold())
                .foregroundStyle(Color.appAccent)
        case .adding:
            ProgressView()
                .controlSize(.regular)
        case .added:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(Color.appAccent)
        }
    }

    private var rowBackground: Color {
        switch state {
        case .idle:
            Color.appControlInactiveFill
        case .adding:
            Color.appControlInactiveFill
        case .added:
            Color.green.opacity(0.12)
        case .failed:
            Color.appAccent.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle, .adding:
            .clear
        case .added:
            .green.opacity(0.35)
        case .failed:
            Color.appAccent.opacity(0.35)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            "Add to \(playlist.name), \(SongCountText.songs(playlist.songCount))"
        case .adding:
            "Adding to \(playlist.name)"
        case .added:
            "Added to \(playlist.name)"
        case .failed:
            "Could not add to \(playlist.name). Tap to retry."
        }
    }
}

private struct AddToPlaylistLoadingRows: View {
    var body: some View {
        CenteredLoadingView(minHeight: 200, label: "Loading playlists")
    }
}

private struct AddToPlaylistPreview: View {
    let playlist: UserPlaylist

    var body: some View {
        ContextPreviewCard {
            PlaylistArtwork(playlist: playlist.asPlaylist(), cornerRadius: 10)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.isPublic ? "Public Playlist" : "Private Playlist")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(SongCountText.songs(playlist.songCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
