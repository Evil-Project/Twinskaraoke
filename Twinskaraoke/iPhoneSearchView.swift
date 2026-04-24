import SwiftUI

struct iPhoneSearchView: View {
    @StateObject var viewModel = PhoneSearchViewModel()
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isSearching {
                    List {
                        ForEach(0..<8, id: \.self) { _ in
                            SearchRowSkeleton()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text("No results for \"\(viewModel.searchText)\"")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundColor(Color.secondary.opacity(0.5))
                        Text("Search for songs or artists")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.results) { song in
                        SearchResultRow(song: song)
                            .onTapGesture { audioManager.play(song: song, context: viewModel.results) }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText, prompt: "Songs, artists…")
        }
    }
}

struct SearchResultRow: View {
    let song: PhoneSong

    var body: some View {
        HStack(spacing: 12) {
            LoadingImage(url: song.imageURL, cornerRadius: 6)
                .frame(width: 52, height: 52)
                .clipped()
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(song.originalArtists?.joined(separator: ", ") ?? "Unknown")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct SearchRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            ShimmerBox(cornerRadius: 6)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerBox(cornerRadius: 4).frame(width: 160, height: 14)
                ShimmerBox(cornerRadius: 4).frame(width: 100, height: 12)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
