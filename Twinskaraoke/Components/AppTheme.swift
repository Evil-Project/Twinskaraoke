import SwiftUI

// MARK: - Color

extension Color {
  /// Apple Music's signature pink-red. Matches the current Music.app accent (≈ #FA2D48).
  static let appAccent = Color(red: 0.98, green: 0.176, blue: 0.282)
}

// MARK: - Apple Music design tokens

/// Centralised design tokens so screens stop hard-coding font sizes / radii / spacings.
/// Values are tuned to match the current Apple Music (iOS) visual language.
enum AM {
  enum Radius {
    /// Inline song-row thumbnails (44–48pt).
    static let thumb: CGFloat = 6
    /// Shelf artwork tiles (~170pt) and grid cells.
    static let card: CGFloat = 6
    /// Hero / full-screen artwork.
    static let hero: CGFloat = 8
    /// Browse category gradient tiles.
    static let tile: CGFloat = 8
    /// Floating popup bar artwork.
    static let popup: CGFloat = 6
    /// Bottom sheets / large surfaces.
    static let sheet: CGFloat = 14
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    /// Standard horizontal margin for screen content.
    static let screenMargin: CGFloat = 16
    /// Spacing between vertically stacked shelves on Home.
    static let shelfSpacing: CGFloat = 28
    /// Width of square shelf artwork.
    static let shelfTile: CGFloat = 170
  }

  enum Font {
    /// Large bold shelf header ("Top Picks", "Recently Played").
    static let sectionHeader = SwiftUI.Font.system(size: 22, weight: .bold)
    /// Smaller section header used inside detail views.
    static let groupHeader = SwiftUI.Font.system(size: 17, weight: .bold)
    /// Title under a tile (1 line, semibold).
    static let tileTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
    /// Caption under a tile (song count, year, etc).
    static let tileCaption = SwiftUI.Font.system(size: 13)
    /// Primary text in song rows.
    static let rowTitle = SwiftUI.Font.system(size: 16, weight: .regular)
    /// Secondary text in song rows.
    static let rowSubtitle = SwiftUI.Font.system(size: 13)
    /// Big title shown on the now-playing screen.
    static let nowPlayingTitle = SwiftUI.Font.system(size: 22, weight: .bold)
    static let nowPlayingArtist = SwiftUI.Font.system(size: 17)
    /// Monospaced timecode beneath the scrubber.
    static let timecode = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Disclosure chevron next to section headers.
    static let chevron = SwiftUI.Font.system(size: 14, weight: .bold)
  }

  enum Shadow {
    static let card = ShadowStyle(color: .black.opacity(0.18), radius: 10, y: 4)
    static let heroIdle = ShadowStyle(color: .black.opacity(0.22), radius: 16, y: 10)
    static let heroPlaying = ShadowStyle(color: .black.opacity(0.45), radius: 28, y: 18)
  }

  struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
  }
}

extension View {
  func amShadow(_ style: AM.ShadowStyle) -> some View {
    self.shadow(color: style.color, radius: style.radius, y: style.y)
  }
}

// MARK: - Reusable section header

/// Apple Music-style shelf header: large bold title with a trailing chevron acting as
/// the "see all" affordance. Tap target spans the full row.
struct AMSectionHeader<Destination: View>: View {
  let title: String
  let destination: Destination?
  init(_ title: String, destination: Destination) {
    self.title = title
    self.destination = destination
  }
  init(_ title: String) where Destination == EmptyView {
    self.title = title
    self.destination = nil
  }
  var body: some View {
    Group {
      if let destination {
        NavigationLink(destination: destination) {
          headerRow(showChevron: true)
        }
        .buttonStyle(.plain)
      } else {
        headerRow(showChevron: false)
      }
    }
    .padding(.horizontal, AM.Spacing.screenMargin)
  }
  private func headerRow(showChevron: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.xs) {
      Text(title)
        .font(AM.Font.sectionHeader)
        .foregroundColor(.primary)
      if showChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.secondary.opacity(0.7))
      }
      Spacer()
    }
    .contentShape(Rectangle())
  }
}
