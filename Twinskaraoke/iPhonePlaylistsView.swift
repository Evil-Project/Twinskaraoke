import SwiftUI

struct iPhonePlaylistsView: View {
    @StateObject var viewModel = PhonePlaylistsViewModel()
    @EnvironmentObject var audioManager: AudioPlayerManager
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.playlists.isEmpty {
                    ProgressView()
                        .padding(.top, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: playlist.imageURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(Color.gray.opacity(0.1))
                                    }
                                    .frame(width: (UIScreen.main.bounds.width - 48) / 2, height: (UIScreen.main.bounds.width - 48) / 2)
                                    .cornerRadius(12)
                                    .clipped()
                                    
                                    Text(playlist.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text("\(playlist.songCount) songs")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, audioManager.currentSong != nil ? 60 : 0)
                }
            }
            .navigationTitle("Playlists")
            .onAppear {
                viewModel.fetchPlaylists()
            }
        }
    }
}

