import SwiftUI

struct WideHomeHero: View {
    let song: Song?
    let context: [Song]
    let playlist: Playlist?
    let secondarySong: Song?
    let secondaryContext: [Song]

    var body: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            WideSongHeroCard(
                eyebrow: "Listen Now",
                title: song?.title ?? playlist?.name ?? "Twinskaraoke",
                subtitle: song?.displayArtist.isEmpty == false ? song?.displayArtist ?? "" : "Fresh karaoke picks for your next session",
                song: song,
                context: context,
                playlist: playlist
            )
            .frame(minWidth: 0, maxWidth: .infinity)

            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                WideHeroModuleTitle(title: "Start Here", subtitle: "Fast actions")
                if let song {
                    WideHeroActionRow(
                        systemImage: "play.fill",
                        title: "Play Latest",
                        subtitle: song.title
                    ) {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.play(song: song, context: context)
                    }
                }
                if let playlist {
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        WideHeroActionRowContent(
                            systemImage: "music.note.list",
                            title: "Open Top Pick",
                            subtitle: playlist.name
                        )
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
                }
                if let secondarySong {
                    WideHeroActionRow(
                        systemImage: "shuffle",
                        title: "Shuffle Mix",
                        subtitle: secondarySong.title
                    ) {
                        AppHaptic.selection.play()
                        AudioPlayerManager.shared.playShuffled(from: secondaryContext.isEmpty ? [secondarySong] : secondaryContext)
                    }
                }
            }
            .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
        }
        .frame(minHeight: 286)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Home.WideHero")
    }
}

struct WideNewHero: View {
    let primary: Song?
    let secondary: Song?
    let context: [Song]
    let playlist: Playlist?

    var body: some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            WideSongHeroCard(
                eyebrow: "New Music",
                title: primary?.title ?? "New",
                subtitle: primary?.displayArtist.isEmpty == false ? primary?.displayArtist ?? "" : "The newest songs and latest releases",
                song: primary,
                context: context,
                playlist: playlist
            )
            .frame(minWidth: 0, maxWidth: .infinity)

            VStack(alignment: .leading, spacing: AM.Spacing.m) {
                WideHeroModuleTitle(title: "Fresh Picks", subtitle: "Updated for large screens")
                if let primary {
                    WideHeroSongRow(song: primary, context: context, label: "Featured Release")
                }
                if let secondary {
                    WideHeroSongRow(song: secondary, context: context.isEmpty ? [secondary] : context, label: "Trending Now")
                }
                if let playlist {
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        WideHeroActionRowContent(
                            systemImage: "square.grid.2x2.fill",
                            title: "New This Week",
                            subtitle: playlist.name
                        )
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
                }
            }
            .frame(width: AM.Layout.wideInspectorWidth, alignment: .topLeading)
        }
        .frame(minHeight: 286)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("New.WideHero")
    }
}

private struct WideSongHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let song: Song?
    let context: [Song]
    let playlist: Playlist?

    var body: some View {
        Button {
            play()
        } label: {
            ZStack(alignment: .bottomLeading) {
                heroArtwork
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.68),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: AM.Spacing.xl) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(eyebrow)
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.72))
                            .textCase(.uppercase)
                        Text(title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }
                    Spacer(minLength: AM.Spacing.l)
                    Image(systemName: "play.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.black)
                        .frame(width: 54, height: 54)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                        .accessibilityHidden(true)
                }
                .padding(AM.Spacing.xl)
            }
            .frame(minHeight: 286)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
                    .strokeBorder(Color.appDivider, lineWidth: 0.8)
            }
            .amShadow(AM.Shadow.heroIdle)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.88, haptic: .selection))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint(song == nil ? "Featured artwork." : "Plays this song.")
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let song {
            RemoteArtworkImage(
                url: song.imageURL,
                cornerRadius: 0,
                contentMode: .fill,
                lowResURL: song.thumbnailURL
            )
                .allowsHitTesting(false)
        } else if let playlist {
            PlaylistArtwork(playlist: playlist, cornerRadius: 0)
                .allowsHitTesting(false)
        } else {
            MusicArtworkPlaceholder(cornerRadius: 0)
                .allowsHitTesting(false)
        }
    }

    private func play() {
        if let song {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: context.isEmpty ? [song] : context)
        }
    }
}

private struct WideHeroModuleTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }
}

private struct WideHeroSongRow: View {
    let song: Song
    let context: [Song]
    let label: String

    var body: some View {
        WideHeroActionRow(systemImage: "play.fill", title: label, subtitle: song.title) {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: context.isEmpty ? [song] : context)
        }
    }
}

private struct WideHeroActionRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WideHeroActionRowContent(systemImage: systemImage, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78, haptic: .selection))
    }
}

private struct WideHeroActionRowContent: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.appControlInactiveFill)
                Image(systemName: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appAccent)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AM.Font.chevron)
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(10)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
    }
}
