import SwiftUI

/// Default star artwork tile, used as fallback cover art for any playlist
/// without remote artwork (including the synthesized "Favorites" playlist).
/// White background with an Apple Music-style pink-to-red gradient star
/// that scales proportionally with the container size.
struct FavoritesArtworkTile: View {
  /// Star size as a fraction of the smaller container dimension. Matches
  /// Apple Music's Favorites tile proportions so the icon looks identical
  /// at any container size.
  var sizeFraction: CGFloat = 0.45
  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.white
        Image(systemName: "star.fill")
          .resizable()
          .scaledToFit()
          .frame(
            width: min(geo.size.width, geo.size.height) * sizeFraction,
            height: min(geo.size.width, geo.size.height) * sizeFraction
          )
          .foregroundStyle(
            LinearGradient(
              colors: [
                Color(red: 1.0, green: 0.18, blue: 0.33),
                Color(red: 1.0, green: 0.36, blue: 0.55),
              ],
              startPoint: .top, endPoint: .bottom
            )
          )
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

/// Renders a playlist's cover art, falling back to a star tile when none is available.
struct PlaylistArtwork: View {
  let playlist: Playlist
  var cornerRadius: CGFloat = 10
  var body: some View {
    Group {
      if playlist.imageURL == nil {
        FavoritesArtworkTile()
      } else {
        LoadingImage(url: playlist.imageURL, cornerRadius: cornerRadius)
      }
    }
  }
}
