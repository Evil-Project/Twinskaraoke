import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

struct FullScreenPlayerView: View {
  @EnvironmentObject var audioManager: AudioPlayerManager
  @StateObject private var favorites = FavoritesManager.shared
  @Environment(\.dismiss) private var dismiss
  @State private var showingQueue = false
  @State private var showLyrics = false
  @State private var showKaraokeControls = false
  @StateObject private var lyricsViewModel = LyricsViewModel()
  @StateObject private var upcomingLyricsViewModel = LyricsViewModel()
  var body: some View {
    if let song = audioManager.currentSong {
      GeometryReader { geo in
        let safeTop = geo.safeAreaInsets.top
        let safeBottom = geo.safeAreaInsets.bottom
        let contentHeight = geo.size.height - safeTop - safeBottom
        let artSize = min(geo.size.width - 64, contentHeight * 0.45, 360)
        ZStack(alignment: .top) {
          Group {
            if audioManager.isRadioMode {
              radioLayout(song: song, artSize: artSize)
            } else {
              musicLayout(song: song, artSize: artSize)
            }
          }
          .padding(.top, safeTop + 6)
          .padding(.bottom, max(0, safeBottom - 8))
          dismissBar
            .padding(.top, 6)
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
      .background(backgroundView(song: song))
      .sheet(isPresented: $showingQueue) {
        Group {
          if audioManager.isRadioMode {
            RadioQueueView()
              .environmentObject(audioManager)
          } else {
            QueueView()
              .environmentObject(audioManager)
          }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .onChange(of: audioManager.currentSong?.id) { newId in
        if showLyrics, !audioManager.isRadioMode, let id = newId {
          if let prefetched = upcomingLyricsViewModel.lyrics.isEmpty
            ? nil : upcomingLyricsViewModel.lyrics,
            upcomingLyricsViewModel.loadedSongID == id
          {
            lyricsViewModel.adopt(songID: id, lyrics: prefetched)
          } else {
            lyricsViewModel.fetch(songID: id)
          }
        }
      }
      .onChange(of: audioManager.upcomingSong?.id) { upcomingId in
        if showLyrics, !audioManager.isRadioMode, let id = upcomingId {
          upcomingLyricsViewModel.fetch(songID: id)
        }
      }
      .onChange(of: audioManager.isRadioMode) { isRadio in
        if isRadio { showLyrics = false }
      }
      .onChange(of: audioManager.showFullScreen) { isShown in
        if !isShown { dismiss() }
      }
      .onAppear { favorites.loadIfNeeded() }
    }
  }
  @ViewBuilder
  private func musicLayout(song: Song, artSize: CGFloat) -> some View {
    VStack(spacing: 0) {
      ZStack {
        if showLyrics {
          VStack(spacing: 0) {
            lyricsHeader(song: song)
            LyricsView(
              lyrics: lyricsViewModel.lyrics,
              currentTime: audioManager.progress * Double(song.duration),
              onSeek: { time in
                guard song.duration > 0 else { return }
                audioManager.seek(to: (time + 0.1) / Double(song.duration))
              }
            )
          }
          .overlay(alignment: .bottomTrailing) {
            karaokeRightDock
              .padding(.trailing, 16)
              .padding(.bottom, 32)
          }
          .transition(.opacity)
        } else {
          VStack(spacing: 0) {
            Spacer(minLength: 20)
            artwork(song: song, size: artSize)
            Spacer(minLength: 28)
            titleRow(song: song)
          }
          .transition(.opacity)
        }
      }
      .frame(maxHeight: .infinity)
      progressSection(song: song)
      controlsRow
        .padding(.horizontal, 12)
        .padding(.top, 40)
      Spacer(minLength: 36)
      volumeRow
      bottomToolbar(song: song)
      Spacer(minLength: 8)
    }
  }
  @ViewBuilder
  private func radioLayout(song: Song, artSize: CGFloat) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 8)
      artwork(song: song, size: artSize)
      Spacer(minLength: 28)
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Circle()
              .fill(Color.appAccent)
              .frame(width: 7, height: 7)
              .scaleEffect(audioManager.isPlaying ? 1.0 : 0.6)
              .animation(
                audioManager.isPlaying
                  ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                  : .default,
                value: audioManager.isPlaying
              )
            Text("LIVE RADIO")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.appAccent)
              .tracking(1.2)
            if let listeners = RadioController.shared.nowPlaying?.listeners {
              Text("·")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
              Text("\(listeners.unique) listening")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
          MarqueeText(
            text: song.title,
            font: .system(size: 22, weight: .bold),
            color: .primary
          )
          Text(song.displayArtist)
            .font(.system(size: 17))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        if canFavoriteRadioSong, let songID = radioFavoriteID {
          Button {
            favorites.toggle(songID: songID)
          } label: {
            Group {
              let isFav = favorites.isFavorite(songID)
              if #available(iOS 17.0, *) {
                Image(systemName: isFav ? "star.fill" : "star")
                  .contentTransition(.symbolEffect(.replace))
              } else {
                Image(systemName: isFav ? "star.fill" : "star")
              }
            }
            .font(.system(size: 24, weight: .regular))
            .foregroundColor(favorites.isFavorite(songID) ? .appAccent : .primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
          }
          .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
        }
      }
      .padding(.horizontal, 32)
      Spacer(minLength: 24)
      Button {
        audioManager.togglePlayPause()
      } label: {
        Group {
          if #available(iOS 17.0, *) {
            Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
          }
        }
        .font(.system(size: 56, weight: .regular))
        .foregroundColor(.primary)
        .frame(width: 88, height: 88)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.6))
      Spacer(minLength: 24)
      volumeRow
      bottomToolbar(song: song)
      Spacer(minLength: 8)
    }
  }
  private var dismissBar: some View {
    Capsule()
      .fill(Color.primary.opacity(0.35))
      .frame(width: 40, height: 5)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture {
        audioManager.showFullScreen = false
      }
  }
  @ViewBuilder
  private func lyricsHeader(song: Song) -> some View {
    HStack(spacing: 12) {
      LoadingImage(
        url: audioManager.displayImageURL(for: song), cornerRadius: 8, contentMode: .fill
      )
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .id(song.id)
      VStack(alignment: .leading, spacing: 2) {
        Text(song.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(1)
        Text(song.displayArtist)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.horizontal, 32)
    .padding(.top, 0)
    .padding(.bottom, 0)
  }
  private func artwork(song: Song, size: CGFloat) -> some View {
    ZStack {
      LoadingImage(
        url: audioManager.displayImageURL(for: song), cornerRadius: AM.Radius.hero,
        contentMode: .fill
      )
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
      .id(song.id)
      .shadow(
        color: .black.opacity(audioManager.isPlaying ? 0.45 : 0.22),
        radius: audioManager.isPlaying ? 28 : 16,
        y: audioManager.isPlaying ? 18 : 10
      )
      .scaleEffect(audioManager.isPlaying ? 1.0 : 0.86)
      .animation(.spring(response: 0.5, dampingFraction: 0.78), value: audioManager.isPlaying)
      if audioManager.isBuffering {
        RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
          .fill(Color.black.opacity(0.4))
          .frame(width: size, height: size)
        LoadingIndicator(size: 64)
      }
    }
    .frame(maxWidth: .infinity)
  }
  @ViewBuilder
  private func titleRow(song: Song) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(song.title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.primary)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(song.displayArtist)
          .font(.system(size: 17))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Button {
        favorites.toggle(songID: song.id)
      } label: {
        Group {
          let isFav = favorites.isFavorite(song.id)
          if #available(iOS 17.0, *) {
            Image(systemName: isFav ? "star.fill" : "star")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: isFav ? "star.fill" : "star")
          }
        }
        .font(.system(size: 24, weight: .regular))
        .foregroundColor(favorites.isFavorite(song.id) ? .appAccent : .primary)
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
    }
    .padding(.horizontal, 32)
  }
  @ViewBuilder
  private func progressSection(song: Song) -> some View {
    AppleMusicProgressBar(
      progress: $audioManager.progress,
      isScrubbing: $audioManager.isEditingProgress,
      onSeekEnd: { fraction in audioManager.seek(to: fraction) }
    )
    .padding(.horizontal, 32)
    .padding(.top, showLyrics ? 0 : 16)
    HStack {
      Text(formattedTime(audioManager.progress * Double(song.duration)))
      Spacer()
      Text(
        formattedTime(
          max(0, Double(song.duration) - audioManager.progress * Double(song.duration))))
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundColor(audioManager.isEditingProgress ? .primary : .secondary)
    .scaleEffect(audioManager.isEditingProgress ? 1.12 : 1.0, anchor: .center)
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: audioManager.isEditingProgress)
    .padding(.horizontal, 32)
    .padding(.top, 2)
  }
  private var controlsRow: some View {
    HStack(spacing: 0) {
      Button {
        audioManager.playPrevious()
      } label: {
        Image(systemName: "backward.fill")
          .font(.system(size: 32))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
      Button {
        audioManager.togglePlayPause()
      } label: {
        Group {
          if #available(iOS 17.0, *) {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .contentTransition(.symbolEffect(.replace))
          } else {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .contentTransition(.opacity)
          }
        }
        .font(.system(size: 48))
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
      Button {
        audioManager.playNextOrRandom()
      } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 32))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.6))
    }
  }
  private var volumeRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "speaker.fill")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
      AppleMusicProgressBar(
        progress: $audioManager.volume,
        isScrubbing: $audioManager.isUserScrubbingVolume,
        onSeekEnd: { _ in },
        trackColor: Color.primary.opacity(0.18),
        fillColor: .primary,
        idleHeight: 7,
        activeHeight: 12
      )
      Image(systemName: "speaker.wave.3.fill")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 32)
    #if canImport(UIKit)
      .background(
        SystemVolumeBridge(
          volume: $audioManager.volume,
          isUserScrubbing: $audioManager.isUserScrubbingVolume
        ).frame(width: 0, height: 0))
    #endif
  }
  @ViewBuilder
  private func bottomToolbar(song: Song) -> some View {
    HStack(spacing: audioManager.isRadioMode ? 56 : 0) {
      if !audioManager.isRadioMode {
        Button {
          withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showLyrics.toggle()
          }
          if showLyrics { lyricsViewModel.fetch(songID: song.id) }
        } label: {
          Image(systemName: "quote.bubble")
            .font(.system(size: 22))
            .foregroundColor(showLyrics ? .primary : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
      }
      #if canImport(UIKit)
        ZStack {
          Image(systemName: routeSymbolName(audioManager.routeIcon))
            .font(.system(size: 22))
            .foregroundColor(.primary)
          AirPlayRoutePickerView()
            .frame(width: 44, height: 44)
        }
        .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
      #endif
      Button {
        showingQueue = true
      } label: {
        Image(systemName: "list.bullet")
          .font(.system(size: 22))
          .foregroundColor(.primary)
          .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
      }
      .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
    }
    .padding(.horizontal, audioManager.isRadioMode ? 0 : 48)
    .padding(.top, 16)
    .frame(maxWidth: .infinity)
  }
  @ViewBuilder
  private var karaokeRightDock: some View {
    VStack(spacing: 12) {
      if showKaraokeControls {
        karaokeVerticalSlider
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      karaokeMicButton
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showKaraokeControls)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: audioManager.karaokeMode)
  }
  private var karaokeMicButton: some View {
    Button {
      if audioManager.karaokeMode {
        audioManager.karaokeMode = false
        showKaraokeControls = false
      } else {
        audioManager.karaokeMode = true
        showKaraokeControls = true
      }
    } label: {
      Image(systemName: audioManager.karaokeMode ? "mic.fill" : "mic")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(audioManager.karaokeMode ? .appAccent : .primary.opacity(0.85))
        .frame(width: 36, height: 36)
        .background(
          Circle()
            .fill(.ultraThinMaterial)
        )
        .overlay(
          Circle()
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.7))
  }
  private var karaokeVerticalSlider: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.slash")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      VerticalKaraokeLevel(
        value: Binding(
          get: { Double(audioManager.karaokeStrength) },
          set: { audioManager.karaokeStrength = Float($0) }
        ),
        enabled: audioManager.karaokeMode,
        onSet: { _ in
          if !audioManager.karaokeMode { audioManager.karaokeMode = true }
        }
      )
      .frame(width: 28, height: 180)
      Image(systemName: "person.wave.2")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(.ultraThinMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
  }
  private var radioFavoriteID: String? {
    RadioController.shared.nowPlaying?.nowPlaying?.song.resolvedSongID
  }
  private var canFavoriteRadioSong: Bool {
    radioFavoriteID != nil
  }
  private func backgroundView(song: Song) -> some View {
    PlayerAmbientBackground(
      artworkURL: audioManager.displayImageURL(for: song),
      isPlaying: audioManager.isPlaying
    )
    .id(song.id)
  }
  private func formattedTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
  }
  private func routeSymbolName(_ name: String) -> String {
    #if canImport(UIKit)
      if UIImage(systemName: name) != nil { return name }
    #endif
    return "airplayaudio"
  }
}

struct GlassCircle: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(in: Circle())
    } else {
      content.background(.white.opacity(0.12), in: Circle())
    }
  }
}
