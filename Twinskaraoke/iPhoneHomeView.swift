import SwiftUI

struct iPhoneHomeView: View {
    @StateObject var viewModel = HomeViewModel()
    @EnvironmentObject var audioManager: AudioPlayerManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let recent = viewModel.recentPlaylist {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Playlist")
                                .font(.title2.bold())
                                .padding(.horizontal)
                            
                            NavigationLink(destination: PlaylistDetailView(playlist: recent)) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 16) {
                                        AsyncImage(url: recent.imageURL) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Color.gray.opacity(0.1)
                                        }
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recent.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("\(recent.songCount) songs")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    
                                    if let songs = recent.songListDTOs {
                                        ForEach(songs.prefix(10)) { song in
                                            Divider().padding(.leading, 76)
                                            HStack(spacing: 12) {
                                                AsyncImage(url: song.imageURL) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    Color.gray.opacity(0.1)
                                                }
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(4)
                                                .clipped()
                                                
                                                VStack(alignment: .leading) {
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
                                            .onTapGesture {
                                                audioManager.play(song: song)
                                            }
                                        }
                                    }
                                }
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(16)
                                .padding(.horizontal)
                            }
                        }
                    }

                    HomeSongSection(title: "Trending", songs: viewModel.trending)
                    
                    if !viewModel.suggestions.isEmpty {
                        HomeSongSection(title: "Suggestions", songs: viewModel.suggestions)
                    }
                }
                .padding(.vertical)
                .padding(.bottom, audioManager.currentSong != nil ? 60 : 0)
            }
            .navigationTitle("Home")
            .onAppear {
                viewModel.fetchHomeData()
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var audioManager: AudioPlayerManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AsyncImage(url: playlist.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.1))
                }
                .frame(width: 200, height: 200)
                .cornerRadius(12)
                .shadow(radius: 10)
                
                Text(playlist.name)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                
                Text("\(playlist.songCount) songs")
                    .foregroundColor(.secondary)
                
                if let songs = playlist.songListDTOs {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            HStack(spacing: 16) {
                                AsyncImage(url: song.imageURL) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.1)
                                }
                                .frame(width: 50, height: 50)
                                .cornerRadius(6)
                                .clipped()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .lineLimit(1)
                                    Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.play(song: song)
                            }
                            Divider().padding(.leading, 82)
                        }
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, audioManager.currentSong != nil ? 60 : 0)
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
                        VStack(alignment: .leading) {
                            AsyncImage(url: song.imageURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.1)
                            }
                            .frame(width: 150, height: 150)
                            .cornerRadius(12)
                            .clipped()
                            
                            Text(song.title)
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                            
                            Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 150)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            audioManager.play(song: song)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
