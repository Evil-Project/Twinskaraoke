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
                    .accessibilityHidden(true)
                TextField("Search", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .frame(minHeight: 44)
                    .onSubmit {
                        viewModel.submitSearch()
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.watchPressable)
                    .accessibilityLabel("Clear Search")
                    .accessibilityHint("Clears the current search text.")
                }
            }
            .padding(.horizontal, 9)
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
                        ProgressView("Searching")
                            .accessibilityValue(trimmedSearchText)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let errorMessage = viewModel.searchErrorMessage {
                    WatchEmptyState(
                        systemImage: "wifi.exclamationmark",
                        title: "Search Unavailable",
                        message: errorMessage
                    )
                    .listRowBackground(Color.clear)

                    Button {
                        viewModel.retrySearch()
                        WatchHaptic.play(.click)
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.watchPressable)
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
                        playableCount: playableSongs.count,
                        isLoading: viewModel.isLoading
                    )
                    .listRowBackground(Color.clear)
                    ForEach(viewModel.results) { item in
                        if let song = item.toSong() {
                            let isCurrent = audioManager.currentSong?.id == song.id
                            Button {
                                play(song, context: playableSongs)
                            } label: {
                                WatchSongRow(
                                    song: song,
                                    isCurrent: isCurrent,
                                    isPlaying: isCurrent && audioManager.isPlaying,
                                    trailingSystemImage: isCurrent ? "chevron.right" : nil
                                )
                            }
                            .buttonStyle(.watchPressable)
                            .accessibilityLabel(isCurrent ? "Open \(song.title)" : song.title)
                            .accessibilityHint(accessibilityHint(for: item))
                        } else {
                            WatchUnavailableSearchRow(item: item)
                        }
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
    }

    private var playableSongs: [Song] {
        viewModel.results.compactMap { $0.toSong() }
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

    private func accessibilityHint(for item: SearchSongItem) -> String {
        guard let song = item.toSong() else {
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

private struct WatchUnavailableSearchRow: View {
    let item: SearchSongItem

    var body: some View {
        HStack(spacing: 10) {
            WatchSongArtwork(url: item.rowImageURL, size: 38)

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

            Spacer(minLength: 4)

            Text("Unavailable")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .opacity(0.68)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("WatchSearch.unavailable.\(item.id)")
    }

    private var accessibilityValue: String {
        let artist = item.originalArtistDisplay
        return artist.isEmpty ? "Unavailable on Apple Watch" : "\(artist), unavailable on Apple Watch"
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
        .accessibilityValue(
            isLoading ? "Updating results for \(query)" : "Results for \(query)"
        )
    }

    private var resultCountText: String {
        let base = totalCount == 1 ? "1 result" : "\(totalCount) results"
        guard playableCount != totalCount else { return base }
        let playable = playableCount == 1 ? "1 playable" : "\(playableCount) playable"
        return "\(base) - \(playable)"
    }
}
