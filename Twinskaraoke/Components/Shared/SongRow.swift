import SwiftUI
import Observation

@MainActor
@Observable
private final class SongDownloadRowState {
    private(set) var status: SongDownloadStatus
    @ObservationIgnored private var observation: ObservationToken?

    init(songID: String) {
        let manager = DownloadManager.shared
        status = manager.status(for: songID)
        // Replaces `statusPublisher(for:).dropFirst().removeDuplicates()`:
        // observation only fires on change (the `dropFirst`), and the guarded
        // assignment below is the `removeDuplicates` — without it every row in
        // a list would re-render on any other song's download progress.
        observation = observeContinuously({
            _ = DownloadManager.shared.downloadedIDs
            _ = DownloadManager.shared.inProgress
        }, onChange: { [weak self] in
            guard let self else { return }
            let next = DownloadManager.shared.status(for: songID)
            if status != next { status = next }
        })
    }
}

enum SongRowSize {
    case compact, regular
    var artSize: CGFloat {
        switch self {
        case .compact: 44
        case .regular: 48
        }
    }

    var cornerRadius: CGFloat {
        AM.Radius.thumb
    }

    var titleFont: Font {
        switch self {
        case .compact: .subheadline
        case .regular: AM.Font.rowTitle
        }
    }

    var subtitleFont: Font {
        switch self {
        case .compact: .caption
        case .regular: AM.Font.rowSubtitle
        }
    }

    var indicatorSize: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 16
        }
    }
}

struct SongRow: View {
    let song: Song
    let size: SongRowSize

    var showsArtwork: Bool = true
    var trailing: AnyView?
    private let playback = PlaybackRowState.shared
    @State private var downloadState: SongDownloadRowState
    @State private var showAddToPlaylist = false
    @Environment(\.appReduceMotion) private var reduceMotion

    init(
        song: Song,
        size: SongRowSize,
        showsArtwork: Bool = true,
        trailing: AnyView? = nil
    ) {
        self.song = song
        self.size = size
        self.showsArtwork = showsArtwork
        self.trailing = trailing
        _downloadState = State(initialValue: SongDownloadRowState(songID: song.id))
    }

    private var isCurrentSong: Bool {
        playback.currentSongID == song.id
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if showsArtwork {
                    RemoteArtworkImage(
                        url: playback.displayImageURL(for: song, variant: .row),
                        cornerRadius: size.cornerRadius,
                        fixedDisplaySize: CGSize(width: size.artSize, height: size.artSize)
                    )
                    .frame(width: size.artSize, height: size.artSize)
                    .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                } else {
                    MusicArtworkPlaceholder(cornerRadius: size.cornerRadius)
                        .frame(width: size.artSize, height: size.artSize)
                }
                if isCurrentSong {
                    RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                        .fill(Color.appArtworkOverlay)
                        .frame(width: size.artSize, height: size.artSize)

                    EqualizerBars(isAnimating: playback.isPlaying)
                        .frame(width: size.indicatorSize, height: size.indicatorSize)
                        .foregroundStyle(.primary)
                }
            }
            .animation(statusAnimation, value: isCurrentSong)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(size.titleFont)
                    .foregroundStyle(isCurrentSong ? Color.appAccent : .primary)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(size.subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Group {
                if downloadState.status.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Downloaded")
                        .transition(statusTransition)
                } else if downloadState.status.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .transition(statusTransition)
                }
            }
            .animation(statusAnimation, value: downloadState.status)
            if !song.durationText.isEmpty {
                Text(song.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let trailing {
                trailing
            } else {
                Menu {
                    songActions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
                .accessibilityLabel("More Actions")
                .accessibilityHint("Shows actions for \(song.title).")
            }
        }
        .padding(.vertical, size == .regular ? 5 : 3)
        .contentShape(Rectangle())
        .contextMenu {
            songActions
        } preview: {
            SongContextPreview(song: song)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
    }

    private var songActions: some View {
        SongActionsMenuItems(song: song) {
            showAddToPlaylist = true
        }
    }

    private var statusAnimation: Animation? {
        reduceMotion ? nil : AppMotion.quick
    }

    private var statusTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }
}

enum MusicGridCardSize: Equatable {
    case regular
    case compact

    var defaultWidth: CGFloat {
        switch self {
        case .regular: AM.Spacing.shelfTile
        case .compact: AM.Spacing.compactShelfTile
        }
    }

    var titleFont: Font {
        switch self {
        case .regular: AM.Font.tileTitle
        case .compact: .subheadline
        }
    }

    var artistFont: Font {
        switch self {
        case .regular: AM.Font.tileCaption
        case .compact: .caption
        }
    }

    var textSpacing: CGFloat {
        switch self {
        case .regular: AM.Spacing.s
        case .compact: 6
        }
    }
}

struct MusicGridCard: View {
    let song: Song
    let context: [Song]
    var size: MusicGridCardSize = .regular
    var width: CGFloat?
    var accessibilityIdentifier: String?
    private let playback = PlaybackRowState.shared
    @State private var showAddToPlaylist = false

    init(
        song: Song,
        context: [Song],
        size: MusicGridCardSize = .regular,
        width: CGFloat? = nil,
        fillsWidth: Bool = false,
        accessibilityIdentifier: String? = nil
    ) {
        self.song = song
        self.context = context
        self.size = size
        self.width = fillsWidth ? nil : (width ?? size.defaultWidth)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var artistText: String {
        song.displayArtist.isEmpty ? String(localized: "Unknown Artist") : song.displayArtist
    }

    var body: some View {
        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.play(song: song, context: context)
        } label: {
            VStack(alignment: .leading, spacing: size.textSpacing) {
                artwork
                Text(song.title)
                    .font(size.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(artistText)
                    .font(size.artistFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(PressableButtonStyle(scale: size == .regular ? 0.97 : 0.96, dim: 0.78, haptic: nil))
        .contextMenu {
            SongActionsMenuItems(song: song) {
                showAddToPlaylist = true
            }
        } preview: {
            SongContextPreview(song: song)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title)
        .accessibilityValue(artistText)
        .accessibilityIdentifier(accessibilityIdentifier ?? "MusicGridCard.\(song.id)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let width {
            artworkContent
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        } else {
            artworkContent
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let imageURL = playback.displayImageURL(for: song, variant: .card) {
            RemoteArtworkImage(
                url: imageURL,
                cornerRadius: AM.Radius.card,
                lowResURL: playback.displayImageURL(for: song, variant: .thumbnail),
                fixedDisplaySize: width.map { CGSize(width: $0, height: $0) }
            )
        } else {
            MusicArtworkPlaceholder(cornerRadius: AM.Radius.card)
        }
    }
}

struct SongActionsMenuItems: View {
    let song: Song
    let onAddToPlaylist: () -> Void
    private let isDownloaded: Bool
    private let isDownloading: Bool
    private let favorites = FavoritesManager.shared
    // Non-nil only inside an editable playlist the user owns; see
    // PlaylistSongRemoval.swift.
    @Environment(\.playlistSongRemoval) private var playlistRemoval

    init(song: Song, onAddToPlaylist: @escaping () -> Void) {
        self.song = song
        self.onAddToPlaylist = onAddToPlaylist

        let downloads = DownloadManager.shared
        isDownloaded = downloads.isDownloaded(song.id)
        isDownloading = downloads.isDownloading(song.id)
    }

    var body: some View {
        Button {
            AppHaptic.selection.play()
            AudioPlayerManager.shared.playNext(song: song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            AppHaptic.selection.play()
            onAddToPlaylist()
        } label: {
            Label("Add to Playlist", systemImage: "plus.circle")
        }

        if let playlistRemoval {
            Button(role: .destructive) {
                AppHaptic.warning.play()
                playlistRemoval.remove(song)
            } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }

        Button {
            let wasFavorite = favorites.isFavorite(song.id)
            favorites.toggle(songID: song.id)
            if wasFavorite {
                AppHaptic.selection.play()
            } else {
                AppHaptic.success.play()
            }
        } label: {
            if favorites.isFavorite(song.id) {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Favorite", systemImage: "star")
            }
        }

        Divider()

        if isDownloaded {
            Button(role: .destructive) {
                AppHaptic.warning.play()
                DownloadManager.shared.remove(songID: song.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else if isDownloading {
            Button {
                AppHaptic.selection.play()
                DownloadManager.shared.cancel(songID: song.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else {
            Button {
                AppHaptic.success.play()
                DownloadManager.shared.download(song: song)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct SongContextPreview: View {
    let song: Song

    var body: some View {
        ContextPreviewCard {
            RemoteArtworkImage(
                url: song.imageURL,
                cornerRadius: 10,
                lowResURL: song.thumbnailURL,
                fixedDisplaySize: CGSize(width: 220, height: 220)
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct SongRowAccessibilityModifier: ViewModifier {
    let song: Song
    var isPending = false
    let onPlay: () -> Void
    private let playback = PlaybackRowState.shared
    @State private var downloadState: SongDownloadRowState
    private let favorites = FavoritesManager.shared

    init(song: Song, isPending: Bool, onPlay: @escaping () -> Void) {
        self.song = song
        self.isPending = isPending
        self.onPlay = onPlay
        _downloadState = State(initialValue: SongDownloadRowState(songID: song.id))
    }

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(song.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Play") {
                onPlay()
            }
            .accessibilityAction(named: "Play Next") {
                AppHaptic.selection.play()
                AudioPlayerManager.shared.playNext(song: song)
            }
            .accessibilityAction(named: favoriteActionTitle) {
                toggleFavorite()
            }
            .accessibilityAction(named: downloadActionTitle) {
                performDownloadAction()
            }
    }

    private var accessibilityValue: String {
        var values = [song.displayArtist]
        if !song.durationText.isEmpty {
            values.append(song.durationText)
        }
        if playback.currentSongID == song.id {
            values.append(playback.isPlaying ? "Now playing" : "Current song")
        }
        if isPending {
            values.append("Loading")
        }
        if favorites.isFavorite(song.id) {
            values.append("Favorite")
        }
        if downloadState.status.isDownloaded {
            values.append("Downloaded")
        } else if downloadState.status.isDownloading {
            values.append("Downloading")
        }
        return values.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isPending {
            return "Preparing playback. More song actions are available from the row menu."
        }
        return "Double tap to play. Swipe up or down for playback and library actions."
    }

    private var favoriteActionTitle: String {
        favorites.isFavorite(song.id) ? "Remove from Favorites" : "Favorite"
    }

    private var downloadActionTitle: String {
        if downloadState.status.isDownloaded {
            return "Remove Download"
        }
        if downloadState.status.isDownloading {
            return "Cancel Download"
        }
        return "Download"
    }

    private func toggleFavorite() {
        let wasFavorite = favorites.isFavorite(song.id)
        favorites.toggle(songID: song.id)
        if wasFavorite {
            AppHaptic.selection.play()
        } else {
            AppHaptic.success.play()
        }
    }

    private func performDownloadAction() {
        let downloads = DownloadManager.shared
        if downloadState.status.isDownloaded {
            AppHaptic.dismiss.play()
            downloads.remove(songID: song.id)
        } else if downloadState.status.isDownloading {
            AppHaptic.selection.play()
            downloads.cancel(songID: song.id)
        } else {
            AppHaptic.success.play()
            downloads.download(song: song)
        }
    }
}

extension View {
    func songRowAccessibility(
        song: Song,
        isPending: Bool = false,
        onPlay: @escaping () -> Void
    ) -> some View {
        modifier(SongRowAccessibilityModifier(song: song, isPending: isPending, onPlay: onPlay))
    }
}
