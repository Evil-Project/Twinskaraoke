import SwiftUI

struct iPhoneHomeView: View {
    @StateObject var viewModel = HomeViewModel()
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if viewModel.isLoading {
                        HomeSkeletonView()
                    } else {
                        if let recent = viewModel.recentPlaylist {
                            RecentPlaylistSection(playlist: recent)
                        }

                        if !viewModel.trending.isEmpty {
                            HomeSongSection(title: "Trending", songs: viewModel.trending)
                        }

                        if !viewModel.suggestions.isEmpty {
                            HomeSongSection(title: "Suggestions", songs: viewModel.suggestions)
                        }
                    }
                }
                .padding(.vertical)
                .padding(.bottom, audioManager.currentSong != nil ? 80 : 16)
            }
            .navigationTitle("Home")
            .onAppear { viewModel.fetchHomeData() }
        }
    }
}

struct RecentPlaylistSection: View {
    let playlist: Playlist
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Playlist")
                .font(.title2.bold())
                .padding(.horizontal)

            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        LoadingImage(url: playlist.imageURL, cornerRadius: 8)
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("\(playlist.songCount) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    if let songs = playlist.songListDTOs {
                        ForEach(songs.prefix(10)) { song in
                            Divider().padding(.leading, 76)
                            PlaylistRow(song: song)
                                .onTapGesture { audioManager.play(song: song, context: songs) }
                        }
                    }
                }
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        }
    }
}

struct PlaylistRow: View {
    let song: PhoneSong

    var body: some View {
        HStack(spacing: 12) {
            LoadingImage(url: song.imageURL, cornerRadius: 4)
                .frame(width: 40, height: 40)
                .clipped()
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(song.originalArtists?.first ?? "Unknown")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LoadingImage(url: playlist.imageURL, cornerRadius: 12)
                    .frame(width: 240, height: 240)
                    .clipped()
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)

                VStack(spacing: 4) {
                    Text(playlist.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("\(playlist.songCount) songs")
                        .foregroundColor(.secondary)
                }

                if let songs = playlist.songListDTOs {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            PlaylistRow(song: song)
                                .onTapGesture { audioManager.play(song: song, context: songs) }
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, audioManager.currentSong != nil ? 80 : 16)
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HomeSongSection: View {
    let title: String
    let songs: [PhoneSong]
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(songs) { song in
                        Button {
                            audioManager.play(song: song, context: songs)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LoadingImage(url: song.imageURL, cornerRadius: 12)
                                    .frame(width: 140, height: 140)
                                    .clipped()
                                    .cornerRadius(12)

                                Text(song.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(song.originalArtists?.joined(separator: ", ") ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct HomeSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                ShimmerBox(cornerRadius: 6)
                    .frame(width: 160, height: 24)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        ShimmerBox(cornerRadius: 8)
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 6) {
                            ShimmerBox(cornerRadius: 4).frame(width: 120, height: 14)
                            ShimmerBox(cornerRadius: 4).frame(width: 70, height: 12)
                        }
                        Spacer()
                    }
                    .padding()
                }
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(16)
                .padding(.horizontal)
            }

            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    ShimmerBox(cornerRadius: 6)
                        .frame(width: 130, height: 24)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<5, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    ShimmerBox(cornerRadius: 12)
                                        .frame(width: 140, height: 140)
                                    ShimmerBox(cornerRadius: 4).frame(width: 110, height: 13)
                                    ShimmerBox(cornerRadius: 4).frame(width: 80, height: 11)
                                }
                                .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}
