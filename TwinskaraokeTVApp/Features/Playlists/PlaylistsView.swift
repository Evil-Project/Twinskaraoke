import SwiftUI

/// The signed-in user's own playlists, plus the entry point for making a new
/// one. Curated playlists live in `LibraryView`; this tab is personal content.
struct PlaylistsView: View {
    let onPlay: (Song, [Song]) -> Void

    private let manager = TVUserPlaylistsManager.shared
    @State private var isCreating = false

    private let cardWidth: CGFloat = 260
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 60)]
    /// Same spacing rationale as `LibraryView`: the `.card` focus lift scales a
    /// poster in place, so each cell needs slack around its artwork or a focused
    /// card grows into its own caption and the row above.
    private let captionGap: CGFloat = 30
    private let rowGap: CGFloat = 80

    var body: some View {
        NavigationStack {
            // No `.navigationTitle`: as in `LibraryView`, the tab bar already
            // labels this screen and a tvOS title floats over the scrolling
            // content instead of reserving space for itself.
            content
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailView(playlist: playlist, onPlay: onPlay)
                }
        }
        .onAppear { manager.loadIfNeeded() }
        .sheet(isPresented: $isCreating) {
            TVCreatePlaylistSheet()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !manager.isSignedIn {
            TVEmptyState(
                systemImage: "person.crop.circle",
                title: "Sign in to see your playlists",
                message: "Open the Account tab and pair this Apple TV with your phone to get your playlists here."
            )
        } else if let error = manager.loadError, manager.playlists.isEmpty {
            TVLoadErrorState(message: error) { manager.load() }
        } else if manager.playlists.isEmpty && manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if manager.playlists.isEmpty {
                    Text("You haven’t made a playlist yet. Create one here, then add songs to it from any of your devices.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 900, alignment: .leading)
                }

                LazyVGrid(columns: columns, spacing: rowGap) {
                    // First cell, so it's where focus lands on an empty account
                    // and stays in a predictable spot once playlists arrive.
                    VStack(alignment: .leading, spacing: captionGap) {
                        Button {
                            isCreating = true
                        } label: {
                            NewPlaylistTile(cornerRadius: 12)
                                .frame(width: cardWidth, height: cardWidth)
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel("Create playlist")

                        TVPosterCaption(
                            title: "New Playlist",
                            subtitle: "Start a playlist",
                            width: cardWidth
                        )
                    }

                    ForEach(manager.playlists) { userPlaylist in
                        let playlist = userPlaylist.asPlaylist()
                        VStack(alignment: .leading, spacing: captionGap) {
                            NavigationLink(value: playlist) {
                                TVArtwork(url: playlist.imageURL)
                                    .frame(width: cardWidth, height: cardWidth)
                            }
                            .buttonStyle(.card)
                            .accessibilityLabel(playlist.name)
                            .accessibilityValue(playlist.songCountText)

                            TVPosterCaption(
                                title: playlist.name,
                                subtitle: playlist.songCountText,
                                width: cardWidth
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
    }
}

/// Placeholder artwork for the create-playlist cell, shaped like the posters
/// beside it so the grid keeps one rhythm.
private struct NewPlaylistTile: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 3, dash: [12, 10])
                    )
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
    }
}
