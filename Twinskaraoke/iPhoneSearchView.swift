import SwiftUI

struct iPhoneSearchView: View {
    @StateObject var viewModel = PhoneSearchViewModel()
    @EnvironmentObject var audioManager: AudioPlayerManager
    
    var body: some View {
        NavigationStack {
            List(viewModel.results) { song in
                HStack(spacing: 16) {
                    AsyncImage(url: song.imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.titleAndArtist)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        
                        Text(song.singerIdentity)
                            .font(.system(size: 14))
                            .foregroundColor(.pink)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    audioManager.play(song: song)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText, prompt: "Search songs...")
            .padding(.bottom, audioManager.currentSong != nil ? 60 : 0)
        }
    }
}

