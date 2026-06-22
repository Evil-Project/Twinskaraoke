import SwiftUI

struct DownloadedSongsView: View {
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var recentlyPlayed = RecentlyPlayedStore.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var localSongs: [Song] = []

    @State private var showsCollapsedTitle = false
    @State private var showRemoveAllConfirmation = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        GeometryReader { geo in
            let viewportSize = sanitizedViewportSize(geo.size)
            ScrollView {
                if localSongs.isEmpty {
                    DownloadedEmptyStateView {
                        refresh()
                    }
                    .frame(width: viewportSize.width, height: max(viewportSize.height - 100, 1))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    VStack(spacing: 18) {
                        heroHeader(width: viewportSize.width)
                        VStack(spacing: 4) {
                            Text("Downloaded")
                                .font(.title2.bold())
                            Text(downloadedSubtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        actionButtons
                            .padding(.horizontal)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(localSongs.enumerated()), id: \.element.id) { idx, song in
                                SongRow(song: song, size: .regular)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        play(song)
                                    }
                                    .songRowAccessibility(song: song) {
                                        play(song)
                                    }
                                    .contextMenu {
                                        DownloadedSongMenuItems(song: song) {
                                            removeDownload(song)
                                        }
                                    } preview: {
                                        SongContextPreview(song: song)
                                    }
                                if idx < localSongs.count - 1 {
                                    Divider().padding(.leading, 76)
                                }
                            }
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    }
                    .padding(.bottom, 16)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DownloadedCollapsedTitleKey.self,
                                value: proxy.frame(in: .named("downloadedScroll")).minY < -180
                            )
                        }
                    )
                }
            }
            .smoothScrolling()
            .coordinateSpace(name: "downloadedScroll")
            .bottomChromeScrollTracking()
            .onPreferenceChange(DownloadedCollapsedTitleKey.self) { collapsed in
                guard showsCollapsedTitle != collapsed else { return }
                showsCollapsedTitle = collapsed
            }
        }
        .navigationTitle(showsCollapsedTitle ? "Downloaded" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !localSongs.isEmpty {
                    DownloadedSongsMenu(
                        playInOrder: playInOrder,
                        shuffle: shuffle,
                        removeAll: requestRemoveAllDownloads
                    )
                }
            }
        }
        .alert("Remove all downloads?", isPresented: $showRemoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Downloads", role: .destructive) {
                removeAllDownloads()
            }
        } message: {
            Text("All offline songs on this device will be removed. You can download them again from song menus.")
        }
        .musicScreenBackground()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsCollapsedTitle)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: localSongs.map(\.id)
        )
        .scrollIndicators(.hidden)
        .refreshable {
            AppHaptic.selection.play()
            refresh()
        }
        .onAppear { refresh() }
        .onChange(of: downloads.downloadedIDs) { _, _ in refresh() }
    }

    private func sanitizedViewportSize(_ size: CGSize) -> CGSize {
        // GeometryReader can briefly report zero, negative, or non-finite dimensions
        // during navigation/layout transitions. Clamp before passing values to
        // frame modifiers so SwiftUI never receives an invalid frame dimension.
        let width = size.width.isFinite ? max(size.width, 1) : 1
        let height = size.height.isFinite ? max(size.height, 1) : 1
        return CGSize(width: width, height: height)
    }

    private var downloadedSubtitle: String {
        let count = localSongs.count == 1 ? "1 song" : "\(localSongs.count) songs"
        guard let duration = downloadedDurationText else { return count }
        return "\(count) • \(duration)"
    }

    private var downloadedDurationText: String? {
        let total = localSongs.reduce(0) { $0 + max(0, $1.duration) }
        guard total > 0 else { return nil }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }

    private func heroHeader(width: CGFloat) -> some View {
        mosaicArtwork
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            .frame(width: width)
            .padding(.top, 12)
    }

    @ViewBuilder
    private var mosaicArtwork: some View {
        let arts = Playlist.songArtworkURLs(localSongs, limit: 4)
        if arts.count > 1 {
            PlaylistMosaicArtwork(urls: arts, cornerRadius: 0, showsLoading: true)
        } else if let url = arts.first {
            RemoteArtworkImage(url: url, cornerRadius: 0)
        } else {
            LinearGradient(
                colors: [Color.appAccent.opacity(0.85), Color.purple.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                playInOrder()
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            .accessibilityLabel("Play downloaded songs")
            Button {
                shuffle()
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            .accessibilityLabel("Shuffle downloaded songs")
        }
    }

    private func refresh() {
        let cached = recentlyPlayed.playlists.flatMap { $0.songListDTOs ?? [] }
        let songs = downloads.downloadedSongs(knownSongs: cached)
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(songs.prefix(18)),
            limit: 18,
            reason: "downloaded songs"
        )
        if reduceMotion {
            localSongs = songs
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                localSongs = songs
            }
        }
    }

    private func playInOrder() {
        guard let first = localSongs.first else { return }
        AudioPlayerManager.shared.playInOrder(song: first, context: localSongs)
    }

    private func shuffle() {
        AudioPlayerManager.shared.playShuffled(from: localSongs)
    }

    private func play(_ song: Song) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: localSongs)
    }

    private func removeDownload(_ song: Song) {
        AppHaptic.warning.play()
        downloads.remove(songID: song.id)
        refresh()
    }

    private func requestRemoveAllDownloads() {
        AppHaptic.warning.play()
        showRemoveAllConfirmation = true
    }

    private func removeAllDownloads() {
        downloads.removeAll()
        AppHaptic.success.play()
        refresh()
    }
}

private struct DownloadedEmptyStateView: View {
    let onRefresh: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var isPulsing = false
    @State private var hasAppeared = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            MusicEmptyStateMark()
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
                .scaleEffect(hasAppeared ? 1 : 0.94)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text("No Downloads")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.primary)
                Text("Save karaoke tracks from any song menu and they will appear here for offline playback.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 340)

            VStack(spacing: AM.Spacing.s) {
                DownloadedEmptyHintRow(
                    title: "Open a song menu",
                    message: "Use a track's context menu from Home, Search, or Library."
                )
                DownloadedEmptyHintRow(
                    title: "Choose Download",
                    message: "Downloaded songs stay playable when the network drops."
                )
            }
            .frame(maxWidth: 360)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)

            MusicEmptyActionButton(title: "Refresh") {
                onRefresh()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .onAppear {
            if reduceMotion {
                hasAppeared = true
                isPulsing = false
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    hasAppeared = true
                }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue {
                isPulsing = false
            } else {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DownloadedEmptyHintRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AM.Spacing.m)
        .padding(.vertical, AM.Spacing.s)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
    }
}

private struct DownloadedSongMenuItems: View {
    let song: Song
    let onRemove: () -> Void
    @ObservedObject private var favorites = FavoritesManager.shared

    var body: some View {
        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playNext(song: song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            let wasFavorite = favorites.isFavorite(song.id)
            favorites.toggle(songID: song.id)
            if wasFavorite {
                AppHaptic.selection.play()
            } else {
                AppHaptic.success.play()
            }
        } label: {
            if favorites.isFavorite(song.id) {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Favorite", systemImage: "star")
            }
        }

        Divider()

        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove Download", systemImage: "trash")
        }
    }
}

private struct DownloadedSongsMenu: View {
    let playInOrder: () -> Void
    let shuffle: () -> Void
    let removeAll: () -> Void

    var body: some View {
        Menu {
            Button {
                AppHaptic.selection.play()
                playInOrder()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                AppHaptic.selection.play()
                shuffle()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Divider()

            Button(role: .destructive) {
                AppHaptic.warning.play()
                removeAll()
            } label: {
                Label("Remove Downloads", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appAccent)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
    }
}

private struct DownloadedCollapsedTitleKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
