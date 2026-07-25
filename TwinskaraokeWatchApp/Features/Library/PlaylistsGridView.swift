import SwiftUI

struct PlaylistsGridView: View {
    @StateObject var viewModel = PlaylistsViewModel()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var loadingAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading, viewModel.playlists.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading Playlists")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            } else if viewModel.playlists.isEmpty {
                WatchEmptyState(
                    systemImage: "music.note.list",
                    title: "No Playlists",
                    message: "Curated playlists will appear here."
                )
                .padding(.horizontal, 10)
                .padding(.top, 16)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    WatchPlaylistsHeader(
                        playlistCount: viewModel.playlists.count,
                        songCount: totalSongCount,
                        isLoading: viewModel.isLoading
                    )

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink(
                                destination: PlaylistDetailView(
                                    playlistID: playlist.id, playlistName: playlist.name
                                )
                            ) {
                                WatchPlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.watchPressable)
                            .simultaneousGesture(TapGesture().onEnded { WatchHaptic.play(.click) })
                            .accessibilityLabel(playlist.name)
                            .accessibilityValue(playlist.songCountText)
                            .accessibilityHint("Opens this playlist.")
                        }
                    }
                    .animation(listAnimation, value: viewModel.playlists.map(\.id))
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Playlists")
        .animation(listAnimation, value: viewModel.playlists.count)
        .animation(loadingAnimation, value: viewModel.isLoading)
        .onAppear {
            viewModel.fetchMusic()
        }
    }

    private var totalSongCount: Int {
        viewModel.playlists.reduce(0) { $0 + max(0, $1.songCount) }
    }
}

private struct WatchPlaylistsHeader: View {
    let playlistCount: Int
    let songCount: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.14))
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appAccent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Playlists")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(summaryText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playlists")
        .accessibilityValue(summaryText)
    }

    private var summaryText: String {
        let playlists = playlistCount == 1 ? "1 playlist" : "\(playlistCount) playlists"
        let songs = songCount == 1 ? "1 song" : "\(songCount) songs"
        return "\(playlists) - \(songs)"
    }
}

private struct WatchPlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.14))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.65))
                    }
                WatchCachedImage(url: playlist.thumbnailURL ?? playlist.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .padding(5)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(playlist.songCountText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(minHeight: 32, alignment: .top)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
