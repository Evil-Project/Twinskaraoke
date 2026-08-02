import Foundation
import SwiftUI

struct ArtistsView: View {
    @State private var viewModel = ArtistsViewModel()
    @State private var searchText = ""


    private var isQueryEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedArtists: [Artist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.artists }
        return viewModel.artists.filter { artist in
            artist.name.localizedCaseInsensitiveContains(query)
                || artist.summary?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        Group {
            if viewModel.artists.isEmpty, viewModel.isLoading {
                ArtistsSkeletonView()
                    .transition(.opacity)
            } else if displayedArtists.isEmpty {
                if viewModel.loadFailed, isQueryEmpty {
                    VStack(spacing: AM.Spacing.l) {
                        MusicEmptyState(
                            title: "Couldn't Load Artists",
                            message: "Check your connection and try again."
                        )
                        MusicEmptyActionButton(title: "Try Again") {
                            AppHaptic.selection.play()
                            viewModel.refresh()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MusicEmptyState(
                        title: isQueryEmpty ? "No Artists" : "No Results",
                        message: isQueryEmpty
                            ? "Artists you load from Twinskaraoke will appear here."
                            : "Try another artist."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List {
                    ForEach(displayedArtists) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist)) {
                            ArtistRow(artist: artist)
                        }
                        .onAppear { viewModel.loadMoreIfNeeded(current: artist) }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .musicScreenBackground()
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Artists"
        )
        .refreshable {
            AppHaptic.selection.play()
            viewModel.refresh()
        }
        .onAppear { viewModel.fetchInitial() }
    }
}

private struct ArtistsSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading artists")
    }
}

private struct ArtistRow: View {
    let artist: Artist
    var body: some View {
        HStack(spacing: 12) {
            ArtistAvatar(url: artist.rowImageURL)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(AM.Font.rowTitle)
                    .lineLimit(1)
                if let count = artist.songCount, count > 0 {
                    Text("\(count) songs")
                        .font(AM.Font.rowSubtitle)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ArtistAvatar: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                RemoteArtworkImage(url: url, cornerRadius: 0)
            } else {
                ArtistAvatarPlaceholder()
            }
        }
    }
}

private struct ArtistAvatarPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(Color.appPlaceholderSecondary)
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.55, height: side * 0.55)
                    .foregroundColor(Color.appPlaceholderPrimary)
                    .offset(y: side * 0.06)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(Circle())
        }
        .accessibilityHidden(true)
    }
}

struct ArtistDetailView: View {
    let artist: Artist
    @State private var loader = ArtistDetailViewModel()
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showsCollapsedTitle = false
    private var current: Artist {
        loader.artist ?? artist
    }

    private var songs: [Song] {
        current.songListDTOs ?? []
    }


    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 18) {
                    parallaxHero(width: geo.size.width)
                    VStack(spacing: 4) {
                        Text(current.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        if let count = current.songCount, count > 0 {
                            Text("\(count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if !songs.isEmpty {
                            Text("\(songs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    if !songs.isEmpty {
                        actionButtons
                        LazyVStack(spacing: 0) {
                            ForEach(songs) { song in
                                ArtistSongRow(song: song, showsArtwork: true) {
                                    play(song)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                Divider().padding(.leading, 76)
                            }
                        }
                    } else if loader.isLoading {
                        ArtistSongsSkeleton()
                    } else if let message = loader.errorMessage {
                        ArtistDetailStateView(
                            title: "Couldn't Load Songs",
                            message: message,
                            buttonTitle: "Try Again"
                        ) {
                            loader.load(id: artist.id, fallback: artist, force: true)
                        }
                    } else if loader.hasLoadedDetail {
                        ArtistDetailStateView(
                            title: "No Songs",
                            message: "Songs by \(current.name) will appear here when they are available.",
                            buttonTitle: "Refresh"
                        ) {
                            loader.load(id: artist.id, fallback: artist, force: true)
                        }
                    }
                    aboutSection
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .smoothScrolling()
            .collapsedNavigationTitle($showsCollapsedTitle)
        }
        .musicScreenBackground()
        .navigationTitle(showsCollapsedTitle ? current.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ArtistActionsMenu(songs: songs)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.92, dim: 0.78, haptic: .selection))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsCollapsedTitle)
        .onAppear { loader.load(id: artist.id, fallback: artist) }
    }

    private func play(_ song: Song) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: songs)
    }

    @ViewBuilder
    private func parallaxHero(width: CGFloat) -> some View {
        let baseSize: CGFloat = 240
        ArtistAvatar(url: current.imageURL)
            .frame(width: baseSize, height: baseSize)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            .frame(width: width)
            .frame(height: baseSize)
            .scrollParallaxHero(
                baseSize: baseSize,
                restingOffset: 12,
                fadesWhenCollapsed: true,
                reduceMotion: reduceMotion
            )
            .padding(.top, 12)
            .contextMenu {
                if !songs.isEmpty {
                    ArtistActionsMenu(songs: songs)
                }
            }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(
                    symbol: "play.fill",
                    text: "Play"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
            Button {
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                LibraryActionButtonLabel(
                    symbol: "shuffle",
                    text: "Shuffle"
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.75, haptic: .medium))
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var aboutSection: some View {
        if let summary = current.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .scaledSystemFont(size: 18, weight: .bold)
                Text(summary)
                    .scaledSystemFont(size: 14)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }
}

private struct ArtistSongRow: View {
    let song: Song

    var showsArtwork = true
    let onPlay: () -> Void

    var body: some View {
        SongRow(song: song, size: .regular, showsArtwork: showsArtwork)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            .songRowAccessibility(song: song) {
                onPlay()
            }
    }
}

private struct ArtistSongsSkeleton: View {
    var body: some View {
        CenteredLoadingView(label: "Loading artist songs")
    }
}

private struct ArtistDetailStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onRefresh: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var hasAppeared = false


    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            MusicEmptyStateMark()
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
                .scaleEffect(hasAppeared ? 1 : 0.94)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text(title)
                    .scaledSystemFont(size: 23, weight: .bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .scaledSystemFont(size: 15)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 340)

            MusicEmptyActionButton(title: buttonTitle) {
                AppHaptic.selection.play()
                onRefresh()
            }

            VStack(spacing: AM.Spacing.s) {
                ArtistDetailHintRow(
                    title: "Artist catalog",
                    message: "Songs appear here as the backend returns this artist's tracks."
                )
                ArtistDetailHintRow(
                    title: "Use song menus",
                    message: "Queue, favorite, download, or add songs to playlists."
                )
            }
            .frame(maxWidth: 360)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.vertical, 24)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                isPulsing = false
                return
            }
            withAnimation(AppMotion.standard) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    isPulsing = false
                    hasAppeared = true
                }
            } else {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ArtistDetailHintRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundColor(.primary)
                Text(message)
                    .scaledSystemFont(size: 13)
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

private struct ArtistActionsMenu: View {
    let songs: [Song]
    private let pendingDownloads: [Song]
    private let downloadingCount: Int

    private var allDownloaded: Bool {
        !songs.isEmpty && pendingDownloads.isEmpty && downloadingCount == 0
    }

    private var downloadTitle: String {
        let downloadedCount = songs.count - pendingDownloads.count - downloadingCount
        return downloadedCount > 0 ? "Download Remaining" : "Download"
    }

    init(songs: [Song]) {
        self.songs = songs

        let downloads = DownloadManager.shared
        pendingDownloads = songs.filter { !downloads.isDownloaded($0.id) && !downloads.isDownloading($0.id) }
        downloadingCount = songs.filter { downloads.isDownloading($0.id) }.count
    }

    var body: some View {
        if songs.isEmpty {
            Text("No Songs")
        } else {
            Button {
                AppHaptic.selection.play()
                if let first = songs.first {
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Divider()

            if downloadingCount > 0 {
                Label("Downloading \(downloadingCount)...", systemImage: "arrow.down.circle")
            } else if allDownloaded {
                Button(role: .destructive) {
                    AppHaptic.warning.play()
                    DownloadManager.shared.remove(songIDs: songs.map(\.id))
                } label: {
                    Label("Remove Downloads", systemImage: "trash")
                }
            } else {
                Button {
                    AppHaptic.success.play()
                    DownloadManager.shared.download(songs: pendingDownloads)
                } label: {
                    Label(downloadTitle, systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
