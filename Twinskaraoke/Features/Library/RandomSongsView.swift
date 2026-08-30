import SwiftUI

struct RandomSongsView: View {
    @State private var viewModel = RandomSongsViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    private var coverURLs: [URL] {
        Playlist.songArtworkURLs(viewModel.songs, limit: 4)
    }

    private var titleSubtitle: String {
        if viewModel.songs.isEmpty {
            return viewModel.isLoading ? "Finding songs" : "A fresh karaoke mix"
        }
        return SongCountText.songs(viewModel.songs.count)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content(width: geo.size.width)
                    .padding(.bottom, 28)
            }
            .smoothScrolling()
        }
        .scrollIndicators(.hidden)
        .musicScreenBackground()
        .navigationTitle("Random")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    RandomSongsToolbarButtonLabel(systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
                .buttonBorderShape(.circle)
                .accessibilityLabel("Refresh Random Songs")
                .accessibilityHint("Loads a new random set.")
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    RandomSongsActionsMenu(
                        playlist: viewModel.playlist,
                        songs: viewModel.songs,
                        onRefresh: refresh
                    )
                } label: {
                    RandomSongsToolbarButtonLabel(systemImage: "ellipsis")
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
                .buttonBorderShape(.circle)
                .accessibilityLabel("More Actions")
            }
        }
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.reload()
            AppHaptic.success.play()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: viewModel.isLoading)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if usesWideOverview(availableWidth: width) {
            wideOverview
                .padding(.top, AM.Spacing.m)
        } else {
            compactOverview(width: width)
                .padding(.top, 12)
        }
    }

    private var wideOverview: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                artwork(size: 280)
                    .contextMenu { menuItems }
                titleBlock(alignment: .leading)
                if !viewModel.songs.isEmpty {
                    actionButtons(songs: viewModel.songs, horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            songsContent(
                songs: viewModel.songs,
                isWideOverview: true,
                rowHorizontalPadding: 0
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RandomSongs.WideOverview")
    }

    private func compactOverview(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            artwork(size: min(248, max(210, width - 96)))
                .contextMenu { menuItems }
            titleBlock(alignment: .center)
            songsContent(songs: viewModel.songs)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func artwork(size: CGFloat) -> some View {
        PlaylistArtworkContent(playlist: viewModel.playlist, coverURLs: coverURLs, cornerRadius: 14)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .amShadow(viewModel.songs.isEmpty ? AM.Shadow.heroIdle : AM.Shadow.heroPlaying)
            .overlay(alignment: .bottomTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(9)
                        .appGlassBackground(in: Circle())
                        .padding(10)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale))
                }
            }
            .accessibilityLabel("Random songs artwork")
    }

    private func titleBlock(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
            Text("Random Songs")
                .font(.title2.bold())
                .multilineTextAlignment(alignment)
            Text(titleSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    @ViewBuilder
    private func songsContent(
        songs: [Song],
        isWideOverview: Bool = false,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !songs.isEmpty {
            VStack(spacing: 0) {
                if !isWideOverview {
                    actionButtons(songs: songs)
                }

                LazyVStack(spacing: 0) {
                    ForEach(songs.enumerated().map { PositionedRandomSong(offset: $0.offset, song: $0.element) }) { item in
                        Button {
                            play(item.song, context: songs)
                        } label: {
                            PlaylistRow(
                                song: item.song,
                                showsArtwork: true,
                                horizontalPadding: rowHorizontalPadding
                            )
                            .contentShape(Rectangle())
                            .songRowAccessibility(song: item.song) {
                                play(item.song, context: songs)
                            }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("RandomSongs.song.\(item.offset).\(item.song.id)")
                        if item.offset < songs.count - 1 {
                            Divider().padding(.leading, rowHorizontalPadding + 60)
                        }
                    }
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        } else if viewModel.isLoading {
            CenteredLoadingView(label: "Loading random songs")
                .transition(.opacity)
        } else {
            RandomSongsStateView(
                title: viewModel.errorMessage == nil ? "No Random Songs" : "Couldn't Load Songs",
                message: viewModel.emptyStateMessage,
                buttonTitle: "Refresh",
                onRefresh: refresh
            )
            .padding(.top, 14)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func actionButtons(
        songs: [Song],
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AppHaptic.selection.play()
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play random songs")

            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle random songs")
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var menuItems: some View {
        RandomSongsActionsMenu(
            playlist: viewModel.playlist,
            songs: viewModel.songs,
            onRefresh: refresh
        )
    }

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: context)
    }

    private func refresh() {
        AppHaptic.selection.play()
        Task {
            await viewModel.reload()
        }
    }
}

/// Row identity for the random songs list. The offset keeps IDs unique when
/// the same song appears twice (duplicate ForEach IDs can hang
/// AttributeGraph). The song fields make the ID change when refresh replaces
/// the whole set at the same offsets: with purely positional identity, an
/// already-composed row keeps showing the previous random pick, and its
/// SongDownloadRowState stays subscribed to the old song's downloads.
private struct PositionedRandomSong: Identifiable {
    struct ID: Hashable {
        let offset: Int
        let songID: String
        let displayArtist: String
        let durationText: String
    }

    let offset: Int
    let song: Song

    var id: ID {
        ID(
            offset: offset,
            songID: song.id,
            displayArtist: song.displayArtist,
            durationText: song.durationText
        )
    }
}

private struct RandomSongsToolbarButtonLabel: View {
    let systemImage: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        iconImage
    }

    private var iconImage: some View {
        Image(systemName: systemImage)
            .font(.headline)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? Color.appAccent : .secondary)
    }
}

private struct RandomSongsStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(title: title, message: message)
            MusicEmptyActionButton(title: buttonTitle) {
                onRefresh()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.vertical, 24)
    }
}

private struct RandomSongsActionsMenu: View {
    let playlist: Playlist
    let songs: [Song]
    let onRefresh: () -> Void

    var body: some View {
        Button {
            onRefresh()
        } label: {
            Label("Refresh Set", systemImage: "arrow.triangle.2.circlepath")
        }

        if !songs.isEmpty {
            Divider()
            PlaylistActionsMenuItems(playlist: playlist, songs: songs)
        }
    }
}
