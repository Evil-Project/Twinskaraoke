import SwiftUI
@MainActor
enum PlaylistEditTarget {
    case favorites
    case playlist(id: String)
    func move(songID: String, from oldOrder: Int, to newOrder: Int) async -> Bool {
        switch self {
        case .favorites:
            await FavoritesManager.shared.moveFavorite(
                songID: songID,
                from: oldOrder,
                to: newOrder
            )
        case let .playlist(id):
            await UserPlaylistsManager.shared.moveSong(
                songID,
                from: oldOrder,
                to: newOrder,
                inPlaylist: id
            )
        }
    }

    func add(songID: String) async -> Bool {
        switch self {
        case .favorites:
            await FavoritesManager.shared.add(songID: songID)
        case let .playlist(id):
            await withCheckedContinuation { continuation in
                UserPlaylistsManager.shared.addSong(songID, toPlaylist: id) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    func currentSongs() async -> [Song]? {
        switch self {
        case .favorites:
            try? await KaraokeAPIClient.favoriteSongs()
        case let .playlist(id):
            try? await KaraokeAPIClient.playlistSongs(id: id)
        }
    }

    func remove(songID: String) async -> Bool {
        switch self {
        case .favorites:
            await FavoritesManager.shared.remove(songID: songID)
        case let .playlist(id):
            await withCheckedContinuation { continuation in
                UserPlaylistsManager.shared.removeSong(songID, fromPlaylist: id) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
struct PlaylistEditSongRow: View {
    let song: Song
    private let playback = PlaybackRowState.shared

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkImage(
                url: playback.displayImageURL(for: song, variant: .row),
                cornerRadius: AM.Radius.thumb,
                fixedDisplaySize: CGSize(width: 48, height: 48)
            )
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(AM.Font.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(AM.Font.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(song.title)
        .accessibilityValue(song.displayArtist)
    }
}
private struct EditableSong: Identifiable, Equatable {
    let id: UUID
    let song: Song

    init(song: Song, id: UUID = UUID()) {
        self.id = id
        self.song = song
    }

    static func == (lhs: EditableSong, rhs: EditableSong) -> Bool {
        lhs.id == rhs.id
    }
}
struct PlaylistEditView: View {
    let playlistName: String
    let target: PlaylistEditTarget
    let onFinish: ([Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var songs: [EditableSong]
    @State private var selection: Set<UUID> = []
    @State private var failureMessage: String?
    @State private var isAddingSongs = false
    @State private var isFinishing = false
    @State private var queueFailed = false
    @State private var pendingWork: Task<Void, Never>?

    init(
        playlistName: String,
        songs: [Song],
        target: PlaylistEditTarget,
        onFinish: @escaping ([Song]) -> Void
    ) {
        self.playlistName = playlistName
        self.target = target
        self.onFinish = onFinish
        _songs = State(initialValue: songs.map { EditableSong(song: $0) })
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(songs) { item in
                PlaylistEditSongRow(song: item.song)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AM.Spacing.screenMargin,
                        bottom: 0,
                        trailing: AM.Spacing.screenMargin
                    ))
                    .listRowBackground(Color.clear)
                    .tag(item.id)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .musicScreenBackground()
        .navigationTitle(playlistName)
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : AppMotion.quick, value: songs)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isFinishing {
                    ProgressView()
                } else {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("PlaylistEdit.done")
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            HStack {
                deleteButton
                Spacer()
                addButton
            }
            .font(.title3)
            .padding(.horizontal, AM.Spacing.screenMargin)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $isAddingSongs) {
            AddSongsToPlaylistView(
                target: target,
                existingSongIDs: Set(songs.map(\.song.id))
            ) { newSongs in
                songs.append(contentsOf: newSongs.map { EditableSong(song: $0) })
            }
        }
        .alert(
            "Couldn't Save Changes",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: {
                    if !$0 {
                        failureMessage = nil
                        queueFailed = false
                    }
                }
            ),
            presenting: failureMessage
        ) { _ in
            Button("OK", role: .cancel) {
                failureMessage = nil
                queueFailed = false
            }
        } message: { message in
            Text(message)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleteSelected()
        } label: {
            Image(systemName: "trash")
        }
        .disabled(selection.isEmpty)
        .accessibilityLabel(
            selection.isEmpty
                ? String(localized: "Delete Selected Songs")
                : String(localized: "Delete \(selection.count) Selected Songs")
        )
        .accessibilityIdentifier("PlaylistEdit.deleteSelected")
    }

    private var addButton: some View {
        Button {
            AppHaptic.selection.play()
            isAddingSongs = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Songs")
        .accessibilityIdentifier("PlaylistEdit.addSongs")
    }
    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        AppHaptic.commit.play()
        let queued = pendingWork
        Task { @MainActor in
            _ = await queued?.result
            onFinish(songs.map(\.song))
            dismiss()
        }
    }
    private func move(from source: IndexSet, to destination: Int) {
        let previous = songs
        var updated = songs
        updated.move(fromOffsets: source, toOffset: destination)
        songs = updated
        AppHaptic.grab.play()

        enqueue { [previous, updated] in
            let targetRows = updated.map(\.id)
            var serverRows = previous

            for targetIndex in targetRows.indices {
                let rowID = targetRows[targetIndex]
                guard let currentIndex = serverRows.firstIndex(where: { $0.id == rowID }),
                      currentIndex != targetIndex,
                      targetIndex < serverRows.count
                else { continue }

                let moved = serverRows[currentIndex]
                let destination = serverRows[targetIndex]
                let ok = await target.move(
                    songID: moved.song.id,
                    from: moved.song.order ?? currentIndex,
                    to: destination.song.order ?? targetIndex
                )
                guard ok else {
                    AppHaptic.error.play()
                    songs = previous
                    queueFailed = true
                    failureMessage = String(
                        localized: "The new order couldn't be saved. Check your connection and try again."
                    )
                    return
                }
                await resync()
                serverRows = songs
            }
            AppHaptic.commit.play()
        }
    }

    private func deleteSelected() {
        remove(songs: songs.filter { selection.contains($0.id) })
    }

    private func remove(songs doomed: [EditableSong]) {
        guard !doomed.isEmpty else { return }
        let previous = songs
        let doomedIDs = Set(doomed.map(\.id))
        songs.removeAll { doomedIDs.contains($0.id) }
        selection.subtract(doomedIDs)
        AppHaptic.selection.play()

        enqueue {
            var failed: [EditableSong] = []
            for item in doomed {
                let ok = await target.remove(songID: item.song.id)
                if !ok { failed.append(item) }
            }
            guard !failed.isEmpty else {
                AppHaptic.success.play()
                await resync()
                return
            }

            AppHaptic.error.play()
            queueFailed = true
            var restored = songs
            let failedIDs = Set(failed.map(\.id))
            for item in previous where failedIDs.contains(item.id) {
                let originalIndex = previous.firstIndex(of: item) ?? restored.count
                restored.insert(item, at: min(originalIndex, restored.count))
            }
            songs = restored
            await resync()
            failureMessage = failed.count == 1
                ? String(localized: "\(failed[0].song.title) couldn't be removed. Check your connection and try again.")
                : String(localized: "\(failed.count) songs couldn't be removed. Check your connection and try again.")
        }
    }
    private func resync() async {
        guard let fresh = await target.currentSongs(), !fresh.isEmpty else { return }
        var identities: [String: [UUID]] = [:]
        for item in songs {
            identities[item.song.id, default: []].append(item.id)
        }
        songs = fresh.map { song in
            guard var available = identities[song.id], !available.isEmpty else {
                return EditableSong(song: song)
            }
            let id = available.removeFirst()
            identities[song.id] = available
            return EditableSong(song: song, id: id)
        }
    }
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previousWork = pendingWork
        pendingWork = Task { @MainActor in
            _ = await previousWork?.result
            guard !Task.isCancelled, !queueFailed else { return }
            await work()
        }
    }
}
