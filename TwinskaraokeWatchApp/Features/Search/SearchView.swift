import SwiftUI

struct SearchView: View {
    @StateObject var viewModel = SearchViewModel()
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showPlayer = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    private var stateAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField("Search", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        WatchHaptic.play(.click)
                    }
                if !trimmedSearchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Clear Search")
                    .accessibilityHint("Clears the current search text.")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            List {
                if trimmedSearchText.isEmpty {
                    WatchEmptyState(
                        systemImage: "magnifyingglass",
                        title: "Search",
                        message: "Find songs, artists, and new favorites."
                    )
                    .listRowBackground(Color.clear)
                } else if viewModel.isLoading, viewModel.results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let loadError = viewModel.loadError, viewModel.results.isEmpty {
                    WatchLoadErrorState(
                        title: "Search Failed",
                        message: loadError,
                        retryAction: { viewModel.performSearch(query: trimmedSearchText) }
                    )
                    .listRowBackground(Color.clear)
                } else if viewModel.results.isEmpty {
                    WatchEmptyState(
                        systemImage: "music.mic",
                        title: "No Results",
                        message: "Try another song title or artist."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    WatchSearchResultsSummary(
                        query: trimmedSearchText,
                        totalCount: viewModel.results.count,
                        playableCount: viewModel.playableSongs.count,
                        isLoading: viewModel.isLoading
                    )
                    .listRowBackground(Color.clear)
                    ForEach(viewModel.resolvedResults) { result in
                        Button {
                            if let song = result.song {
                                play(song, context: viewModel.playableSongs)
                            } else {
                                WatchHaptic.play(.failure)
                            }
                        } label: {
                            if let song = result.song {
                                let isCurrent = audioManager.currentSong?.id == song.id
                                WatchSongRow(
                                    song: song,
                                    isCurrent: isCurrent,
                                    isPlaying: isCurrent && audioManager.isPlaying,
                                    trailingSystemImage: isCurrent
                                        ? (audioManager.isPlaying ? "pause.fill" : "play.fill")
                                        : nil
                                )
                            } else {
                                let item = result.item
                                HStack(spacing: 10) {
                                    WatchSongArtwork(url: item.rowImageURL, size: 38)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(item.originalArtistDisplay)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 3)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(item.title)
                                .accessibilityValue(item.originalArtistDisplay)
                                .accessibilityHint("This result cannot be played on Apple Watch.")
                            }
                        }
                        .buttonStyle(.watchPressable)
                        .accessibilityHint(accessibilityHint(for: result))
                    }
                }
            }
        }
        .navigationTitle("Search")
        .animation(stateAnimation, value: viewModel.searchText)
        .animation(stateAnimation, value: audioManager.currentSong?.id)
        .animation(stateAnimation, value: viewModel.results.count)
        .animation(stateAnimation, value: viewModel.isLoading)
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(audioManager)
        }
        .onAppear {
            prefetchArtwork()
        }
        .compatibleOnChange(of: viewModel.resolvedResults.map(\.id)) { _ in
            prefetchArtwork()
        }
        .onDisappear {
            WatchArtworkPrefetcher.shared.cancel(reason: "search")
        }
    }

    private func prefetchArtwork() {
        let urls = viewModel.resolvedResults.compactMap { $0.song?.rowImageURL ?? $0.item.rowImageURL }
        WatchArtworkPrefetcher.shared.prefetch(urls: urls, reason: "search")
    }

    private var trimmedSearchText: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func play(_ song: Song, context: [Song]) {
        if audioManager.currentSong?.id != song.id {
            audioManager.play(song: song, context: context)
            WatchHaptic.play(.start)
        } else {
            WatchHaptic.play(.click)
        }
        showPlayer = true
    }

    private func accessibilityHint(for result: WatchSearchResult) -> String {
        guard let song = result.song else {
            return "This result cannot be played on Apple Watch."
        }
        if audioManager.currentSong?.id == song.id {
            return "Double tap to open the current song."
        }
        return "Double tap to play this result."
    }

    private func clearSearch() {
        viewModel.searchText = ""
        WatchHaptic.play(.click)
    }
}

private struct WatchSearchResultsSummary: View {
    let query: String
    let totalCount: Int
    let playableCount: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appAccent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(resultCountText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("Results for \"\(query)\"")
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
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultCountText)
        .accessibilityValue("Results for \(query)")
    }

    private var resultCountText: String {
        let base = totalCount == 1 ? "1 result" : "\(totalCount) results"
        guard playableCount != totalCount else { return base }
        let playable = playableCount == 1 ? "1 playable" : "\(playableCount) playable"
        return "\(base) - \(playable)"
    }
}
