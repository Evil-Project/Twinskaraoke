import SwiftUI

struct HomeView: View {
    let onPlay: (Song, [Song]) -> Void

    @Environment(AudioManager.self) private var audioManager
    @State private var viewModel = HomeViewModel()

    var body: some View {
        Group {
            if let error = viewModel.loadError, viewModel.trending.isEmpty {
                TVLoadErrorState(message: error) { viewModel.fetch() }
            } else if viewModel.trending.isEmpty && viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .onAppear { viewModel.fetch() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                shelf(title: "Trending", subtitle: "What everyone's singing", songs: viewModel.trending)
                if !viewModel.latest.isEmpty {
                    shelf(title: "New Releases", subtitle: "Fresh from the catalog", songs: viewModel.latest)
                }
            }
            .padding(.vertical, 60)
        }
    }

    private func shelf(title: String, subtitle: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            TVSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(songs) { song in
                        let isCurrent = audioManager.currentSong?.id == song.id
                        TVSongCard(
                            song: song,
                            isCurrent: isCurrent,
                            isPlaying: isCurrent && audioManager.isPlaying
                        ) {
                            onPlay(song, songs)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }
}
