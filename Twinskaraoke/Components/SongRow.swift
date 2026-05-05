import SwiftUI

enum SongRowSize {
  case compact, regular
  var artSize: CGFloat {
    switch self {
    case .compact: return 44
    case .regular: return 48
    }
  }
  var cornerRadius: CGFloat { AM.Radius.thumb }
  var titleFont: Font {
    switch self {
    case .compact: return .system(size: 15, weight: .regular)
    case .regular: return AM.Font.rowTitle
    }
  }
  var subtitleFont: Font {
    switch self {
    case .compact: return .system(size: 12)
    case .regular: return AM.Font.rowSubtitle
    }
  }
  var indicatorSize: CGFloat {
    switch self {
    case .compact: return 14
    case .regular: return 16
    }
  }
}

struct SongRow: View {
  let song: Song
  let size: SongRowSize
  var trailing: AnyView? = nil
  @EnvironmentObject var audioManager: AudioPlayerManager
  @StateObject private var downloads = DownloadManager.shared
  private var isCurrentSong: Bool { audioManager.currentSong?.id == song.id }
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        LoadingImage(url: audioManager.displayImageURL(for: song), cornerRadius: size.cornerRadius)
          .frame(width: size.artSize, height: size.artSize)
          .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        if isCurrentSong {
          RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.4))
            .frame(width: size.artSize, height: size.artSize)
          EqualizerBars(isAnimating: audioManager.isPlaying)
            .frame(width: size.indicatorSize, height: size.indicatorSize)
            .foregroundColor(.white)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(size.titleFont)
          .foregroundColor(isCurrentSong ? .appAccent : .primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(size.subtitleFont)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if downloads.isDownloaded(song.id) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      } else if downloads.isDownloading(song.id) {
        LoadingIndicator(size: 18)
      }
      if !song.durationText.isEmpty {
        Text(song.durationText)
          .font(.system(size: 13, design: .rounded))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }
      if let trailing {
        trailing
      } else {
        Menu {
          Button {
            audioManager.play(song: song)
          } label: {
            Label("Play Next", systemImage: "text.insert")
          }
          if downloads.isDownloaded(song.id) {
            Button(role: .destructive) {
              downloads.remove(songID: song.id)
            } label: {
              Label("Remove Download", systemImage: "trash")
            }
          } else if downloads.isDownloading(song.id) {
            Button {
              downloads.cancel(songID: song.id)
            } label: {
              Label("Cancel Download", systemImage: "xmark.circle")
            }
          } else {
            Button {
              downloads.download(song: song)
            } label: {
              Label("Download", systemImage: "arrow.down.circle")
            }
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
      }
    }
    .contentShape(Rectangle())
  }
}

struct SongRowSkeleton: View {
  let size: SongRowSize
  var body: some View {
    HStack {
      Spacer()
      LoadingIndicator(size: 32)
      Spacer()
    }
    .frame(height: size.artSize)
    .padding(.vertical, 4)
  }
}
