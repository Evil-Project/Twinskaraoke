import SwiftUI

struct QueueRow: View {
    let song: Song
    let position: Int
    let isPlayingNext: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    @Environment(AudioPlayerManager.self) private var audioManager
    @State private var showAddToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        RemoteArtworkImage(
                            url: audioManager.displayImageURL(for: song, variant: .row),
                            cornerRadius: AM.Radius.thumb,
                            lowResURL: song.thumbnailURL
                        )
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
                        if isPlayingNext {
                            Text("NEXT")
                                .font(AM.Font.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.appAccent))
                                .padding(5)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(AM.Font.rowTitle.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(song.displayArtist)
                            .font(AM.Font.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .contextMenu {
                SongActionsMenuItems(song: song) {
                    showAddToPlaylist = true
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "text.badge.minus")
                }
            } preview: {
                SongContextPreview(song: song)
                    .environment(audioManager)
            }
            .accessibilityLabel("\(position). \(song.title), \(song.displayArtist)")
            .accessibilityValue(isPlayingNext ? "Playing next" : "Queued")
            .accessibilityHint("Plays this song from the queue.")
            Menu {
                SongActionsMenuItems(song: song) {
                    showAddToPlaylist = true
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "text.badge.minus")
                }
            } label: {
                Label("More actions", systemImage: "ellipsis")
                    .font(AM.Font.groupHeader)
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
            .accessibilityLabel("More actions")
            .accessibilityHint("Shows actions for \(song.title).")
        }
        .padding(.vertical, 3)
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .accessibilityAction(named: "Play") {
            onPlay()
        }
        .accessibilityAction(named: "Add to Playlist") {
            AppHaptic.selection.play()
            showAddToPlaylist = true
        }
        .accessibilityAction(named: "Remove from Queue") {
            onRemove()
        }
    }
}

struct QueueModeButton: View {
    let symbol: String
    let isActive: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let action: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if !reduceMotion {
                    Image(systemName: symbol)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(AM.Font.groupHeader)
            .foregroundStyle(isActive ? Color.appControlActiveForeground : .primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .modifier(QueueModeBackground(isActive: isActive))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.75, haptic: .selection))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double tap to toggle.")
    }
}

struct QueueModeBackground: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            content.background(Capsule().fill(Color.appControlActiveFill))
        } else {
            content.glassEffect(in: Capsule())
        }
    }
}
