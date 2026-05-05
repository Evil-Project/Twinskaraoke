import SwiftUI

struct RadioView: View {
  @StateObject private var radio = RadioController.shared
  @EnvironmentObject var audioManager: AudioPlayerManager
  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
          if radio.nowPlaying == nil {
            RadioSkeletonView()
              .transition(.opacity)
          } else {
            VStack(spacing: 24) {
              stationCard
              hostedStationsSection
              featuredShowsSection
              if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
                historySection(history: history)
              }
            }
            .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.4), value: radio.nowPlaying == nil)
        .padding(.vertical, 12)
      }
      .navigationTitle("Radio")
      .onAppear { radio.start() }
    }
  }
  @ViewBuilder
  private var stationCard: some View {
    let np = radio.nowPlaying
    let song = np?.nowPlaying?.song
    let isLivePlaying = audioManager.isRadioMode && audioManager.isPlaying
    let isOnLiveStation = audioManager.isRadioMode && audioManager.currentSong != nil
    VStack(spacing: 14) {
      ZStack(alignment: .topLeading) {
        Group {
          if let art = song?.art, let url = URL(string: art) {
            LoadingImage(url: url, cornerRadius: 14, contentMode: .fill)
          } else {
            artPlaceholder
          }
        }
        HStack(spacing: 4) {
          Circle()
            .fill(.white)
            .frame(width: 5, height: 5)
          Text("LIVE")
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(.white)
            .tracking(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.appAccent))
        .padding(10)
      }
      .frame(maxWidth: 280, maxHeight: 280)
      .aspectRatio(1, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
      .padding(.horizontal, 32)
      VStack(spacing: 6) {
        Text(song?.title ?? np?.station.name ?? "Neuro 21 Station")
          .font(.title3.bold())
          .multilineTextAlignment(.center)
          .lineLimit(2)
        Text(song?.artist ?? np?.station.description ?? "")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(1)
        if let listeners = np?.listeners {
          Text("\(listeners.unique) listening")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
      }
      .padding(.horizontal, 24)
      Button {
        if isOnLiveStation {
          audioManager.togglePlayPause()
        } else {
          radio.playLiveStream()
        }
      } label: {
        ZStack {
          Circle()
            .fill(Color.appAccent)
            .frame(width: 64, height: 64)
          if audioManager.isBuffering && audioManager.isRadioMode && !audioManager.isPlaying {
            LoadingIndicator(size: 36)
          } else {
            Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 26, weight: .medium))
              .foregroundColor(.white)
              .offset(x: isLivePlaying ? 0 : 2)
          }
        }
      }
      .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.85))
      if let next = np?.playingNext?.song {
        HStack(spacing: 12) {
          if let art = next.art, let url = URL(string: art) {
            LoadingImage(url: url, cornerRadius: 6)
              .frame(width: 48, height: 48)
              .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color.secondary.opacity(0.15))
              .frame(width: 48, height: 48)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("Up Next")
              .font(.caption.weight(.semibold))
              .foregroundColor(.secondary)
            Text(next.title ?? next.text ?? "")
              .font(.system(size: 15, weight: .semibold))
              .lineLimit(1)
            Text(next.artist ?? "")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
          Spacer()
        }
        .padding(.horizontal, 16)
      }
    }
  }
  @ViewBuilder
  private var artPlaceholder: some View {
    LinearGradient(
      colors: [Color.appAccent, Color.purple],
      startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay(
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.system(size: 64, weight: .medium))
        .foregroundColor(.white.opacity(0.85))
    )
  }
  private func historySection(history: [RadioNowPlaying.HistoryItem]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recently Played")
        .font(.title3.bold())
        .padding(.horizontal, 16)
      LazyVStack(spacing: 0) {
        ForEach(Array(history.prefix(10).enumerated()), id: \.offset) { _, item in
          RadioHistoryRow(song: item.song)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
          Divider().padding(.leading, 76)
        }
      }
    }
  }
  private var hostedStationsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Hosted Stations")
        .font(.title3.bold())
        .padding(.horizontal, 16)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(RadioStationTile.hosted) { tile in
            RadioStationTileView(tile: tile)
          }
        }
        .padding(.horizontal, 16)
      }
    }
  }
  private var featuredShowsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Featured Shows")
        .font(.title3.bold())
        .padding(.horizontal, 16)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(RadioShowTile.featured) { tile in
            RadioShowTileView(tile: tile)
          }
        }
        .padding(.horizontal, 16)
      }
    }
  }
}

private struct RadioStationTile: Identifiable {
  let id = UUID()
  let name: String
  let tagline: String
  let gradient: [Color]
  static let hosted: [RadioStationTile] = [
    .init(
      name: "Twinskaraoke 1", tagline: "Worldwide",
      gradient: [
        Color(red: 0.95, green: 0.20, blue: 0.30), Color(red: 0.45, green: 0.05, blue: 0.10),
      ]),
    .init(
      name: "Twinskaraoke Hits", tagline: "Decades of hits",
      gradient: [
        Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.05, green: 0.15, blue: 0.45),
      ]),
    .init(
      name: "Twinskaraoke Country", tagline: "Today's country",
      gradient: [
        Color(red: 0.85, green: 0.55, blue: 0.20), Color(red: 0.40, green: 0.20, blue: 0.05),
      ]),
  ]
}

private struct RadioStationTileView: View {
  let tile: RadioStationTile
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topLeading) {
        LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        HStack(spacing: 4) {
          Circle().fill(.white).frame(width: 5, height: 5)
          Text("LIVE")
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(.white)
            .tracking(0.6)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.appAccent))
        .padding(8)
      }
      .frame(width: 200, height: 200)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text(tile.name)
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
      Text(tile.tagline)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(width: 200)
  }
}

private struct RadioShowTile: Identifiable {
  let id = UUID()
  let title: String
  let host: String
  let gradient: [Color]
  static let featured: [RadioShowTile] = [
    .init(
      title: "The Zane Lowe Show", host: "Zane Lowe",
      gradient: [
        Color(red: 0.55, green: 0.10, blue: 0.55), Color(red: 0.20, green: 0.05, blue: 0.30),
      ]),
    .init(
      title: "Ebro Darden", host: "Hip-Hop",
      gradient: [
        Color(red: 0.10, green: 0.55, blue: 0.55), Color(red: 0.05, green: 0.25, blue: 0.30),
      ]),
    .init(
      title: "Travis Mills", host: "The Pop Show",
      gradient: [
        Color(red: 0.95, green: 0.40, blue: 0.65), Color(red: 0.45, green: 0.10, blue: 0.30),
      ]),
    .init(
      title: "Kelleigh Bannen", host: "Today's Country",
      gradient: [
        Color(red: 0.85, green: 0.65, blue: 0.30), Color(red: 0.45, green: 0.30, blue: 0.05),
      ]),
  ]
}

private struct RadioShowTileView: View {
  let tile: RadioShowTile
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: "mic.fill")
          .font(.system(size: 26, weight: .medium))
          .foregroundColor(.white.opacity(0.85))
          .padding(12)
      }
      .frame(width: 160, height: 160)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text(tile.title)
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)
      Text(tile.host)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(width: 160)
  }
}

private struct RadioHistoryRow: View {
  let song: RadioNowPlaying.SongInfo
  var body: some View {
    HStack(spacing: 12) {
      if let art = song.art, let url = URL(string: art) {
        LoadingImage(url: url, cornerRadius: 6)
          .frame(width: 48, height: 48)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.secondary.opacity(0.15))
          .frame(width: 48, height: 48)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title ?? song.text ?? "")
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
        Text(song.artist ?? "")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
  }
}

struct RadioSkeletonView: View {
  var body: some View {
    LoadingIndicator(size: 64)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 80)
  }
}
