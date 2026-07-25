import SwiftUI
import Combine

struct BrowseSongCollectionView: View {
    let title: String
    let songs: [Song]
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsCollapsedTitle = false
    @State private var fallbackHeroURL: URL?

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }


    init(title: String, songs: [Song]) {
        self.title = title
        self.songs = songs
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                collectionOverview(width: geo.size.width)
                    .tabBarBottomPadding()
            }
            .smoothScrolling()
            .collapsedNavigationTitle($showsCollapsedTitle)
        }
        .navigationTitle(showsCollapsedTitle ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .animation(
            reduceMotion ? nil : AppMotion.quick,
            value: showsCollapsedTitle
        )
    }

    @ViewBuilder
    private func collectionOverview(width: CGFloat) -> some View {
        if usesWideOverview(availableWidth: width) {
            wideCollectionOverview
        } else {
            compactCollectionOverview(width: width)
        }
    }

    private func compactCollectionOverview(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            parallaxHero(width: width)
            collectionTitleBlock(alignment: .center)
            songsContent()
        }
    }

    private var wideCollectionOverview: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                heroArtwork
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
                    .amShadow(AM.Shadow.heroIdle)
                collectionTitleBlock(alignment: .leading)
                if !songs.isEmpty {
                    actionButtons(horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            songsContent(isWideOverview: true, rowHorizontalPadding: 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.top, AM.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("BrowseSongCollection.WideOverview")
    }

    private func play(_ song: Song) {
        AppHaptic.selection.play()
        AudioPlayerManager.shared.play(song: song, context: songs)
    }

    @ViewBuilder
    private func parallaxHero(width _: CGFloat) -> some View {
        let baseSize: CGFloat = 240
        heroArtwork
            .frame(width: baseSize, height: baseSize)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
            .amShadow(AM.Shadow.heroIdle)
            .frame(maxWidth: .infinity)
            .frame(height: baseSize)
            .scrollParallaxHero(
                baseSize: baseSize,
                restingOffset: 8,
                reduceMotion: reduceMotion
            )
            .padding(.top, 8)
    }

    private func collectionTitleBlock(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(alignment)
            Text(songCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    private var songCountText: String {
        songs.count == 1 ? "1 song" : "\(songs.count) songs"
    }

    @ViewBuilder
    private var heroArtwork: some View {
        let heroSong = songs.first(where: { $0.hasOwnArtwork })
        // The random fallback is picked once per collection; drawing it in
        // `body` directly would swap the hero image on every re-render.
        let artURL = heroSong?.imageURL ?? fallbackHeroURL
        RemoteArtworkImage(url: artURL, cornerRadius: 0, contentMode: .fill, lowResURL: heroSong?.thumbnailURL)
            .onAppear {
                pickFallbackHeroURLIfNeeded()
            }
            .onReceive(FallbackArtProvider.shared.objectWillChange) { _ in
                pickFallbackHeroURLIfNeeded()
            }
    }

    private func pickFallbackHeroURLIfNeeded() {
        guard fallbackHeroURL == nil else { return }
        fallbackHeroURL = FallbackArtProvider.shared.randomURL
    }

    @ViewBuilder
    private func songsContent(
        isWideOverview: Bool = false,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !songs.isEmpty {
            VStack(spacing: 0) {
                if !isWideOverview {
                    actionButtons()
                }
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        Button {
                            play(song)
                        } label: {
                            SongRow(song: song, size: .regular, showsArtwork: true)
                                .padding(.horizontal, rowHorizontalPadding)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: song) {
                                    play(song)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("BrowseSongCollection.song.\(song.id)")
                        Divider().padding(.leading, rowHorizontalPadding + 60)
                    }
                }
            }
        } else {
            MusicEmptyState(
                title: "No Songs",
                message: "This collection does not have playable songs yet."
            )
            .padding(.top, AM.Spacing.s)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func actionButtons(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
        HStack(spacing: AM.Spacing.m) {
            Button {
                if let first = songs.first {
                    AppHaptic.medium.play()
                    AudioPlayerManager.shared.playInOrder(song: first, context: songs)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play \(title)")
            .accessibilityValue("\(songs.count) songs")
            Button {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playShuffled(from: songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle \(title)")
            .accessibilityValue("\(songs.count) songs")
        }
        .padding(.horizontal, horizontalPadding)
    }
}
