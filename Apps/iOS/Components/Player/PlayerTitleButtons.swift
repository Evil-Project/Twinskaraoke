import SwiftUI

/// The soft filled circle the player's actions sit on, Apple Music's treatment
/// for favorite, more and the queue-mode badge on Playing Next. It is a theme
/// token rather than a literal grey here so the three title surfaces and the
/// badge in ``PlayerBottomToolbar`` cannot drift apart.
///
/// Computed, not a `let`: a global `let` is initialised once, on first use,
/// and would keep whichever theme was active then.
private var playerTitleButtonBackground: Color {
    Color.appPlayerActionFill
}

/// A website theme lights an active action — a saved favourite — in its
/// primary. Every other theme keeps the glyph white either way.
func playerTitleIconColor(isActive: Bool = false) -> Color {
    guard isActive, let primary = AppThemeStore.shared.palette?.primary else { return .primary }
    return primary
}

/// How far the filled circle sits inside the button's hit target. The tap area
/// stays a full 44pt; only the circle shrinks, so it hugs the glyph the way
/// Apple Music's does instead of filling the whole target.
private let playerTitleButtonChromeInset: CGFloat = 10

extension View {
    /// The circular background worn by the player's title-surface buttons, and
    /// the hit target underneath it. The iPad control bar sits on its own glass
    /// and skips the circle, but keeps the target.
    @ViewBuilder
    func playerTitleButtonChrome(_ isVisible: Bool, size: CGFloat) -> some View {
        if isVisible {
            playerControlGlyphScaling().frame(
                width: size - playerTitleButtonChromeInset,
                height: size - playerTitleButtonChromeInset
            )
            .background(playerTitleButtonBackground, in: Circle())
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        } else {
            playerControlGlyphScaling().frame(width: size, height: size)
                .contentShape(Rectangle())
        }
    }
}

/// The favorite toggle shared by the player's three title surfaces: the compact
/// title row, the compact lyrics header and the iPad landscape control bar.
/// They differ only in metrics and chrome, so the toggle, haptics, symbol
/// effect and accessibility live here rather than in triplicate.
struct PlayerFavoriteButton: View {
    let song: Song
    var font: Font = .title3
    var size: CGFloat = 44
    var showsChrome: Bool = true

    private let favorites = FavoritesManager.shared
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        let isFavorite = favorites.isFavorite(song.id)
        Button {
            let wasFavorite = favorites.isFavorite(song.id)
            favorites.toggle(songID: song.id)
            if wasFavorite {
                AppHaptic.selection.play()
            } else {
                AppHaptic.success.play()
            }
        } label: {
            Group {
                if !reduceMotion {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isFavorite)
                } else {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
            }
            .font(font)
            .foregroundStyle(playerTitleIconColor(isActive: isFavorite))
            .playerTitleButtonChrome(showsChrome, size: size)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        // Signed out there is nothing to save a favorite to. Dimmed rather
        // than hidden, so the title row keeps its shape.
        .disabled(!favorites.isAvailable)
        .opacity(favorites.isAvailable ? 1 : 0.4)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityValue(song.title)
        .accessibilityHint(
            favorites.isAvailable
                ? String(localized: "Updates favorites for the current song.")
                : String(localized: "Sign in to use favorites.")
        )
    }
}

/// The overflow menu paired with ``PlayerFavoriteButton`` on the same three
/// surfaces.
struct PlayerMoreMenu: View {
    let song: Song
    var font: Font = AM.Font.playerGlyph
    var size: CGFloat = 44
    var showsChrome: Bool = true
    let onAddToPlaylist: () -> Void

    var body: some View {
        Menu {
            SleepTimerMenu()
            Divider()
            SongActionsMenuItems(song: song, onAddToPlaylist: onAddToPlaylist)
        } label: {
            Image(systemName: "ellipsis")
                .font(font)
                .foregroundStyle(playerTitleIconColor())
                .playerTitleButtonChrome(showsChrome, size: size)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6, haptic: .selection))
        .accessibilityLabel("More")
        .accessibilityValue(song.title)
    }
}
