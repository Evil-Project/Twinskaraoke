import SwiftUI

/// Which collection an edit session writes through to.
///
/// Favorites and a personal playlist present the same editing UI but share no
/// routes: membership, ordering and removal each live somewhere different, and
/// Favorites has no playlist ID at all. Keeping the two behind one type means
/// `PlaylistEditView` never branches on `isFavorites`.
@MainActor
enum PlaylistEditTarget {
    case favorites
    case playlist(id: String)

    /// Moves one song from `oldOrder` to `newOrder`; the endpoint takes a single
    /// move per call, and needs both ends of it.
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

    /// The collection as the server currently has it, ordering included.
    ///
    /// Both mutating calls invalidate their cache first, so this reads through
    /// to the network rather than returning the pre-mutation payload.
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

/// An editor row: artwork, title, artist, nothing else.
///
/// Deliberately not `PlaylistRow`/`SongRow`, which hard-code a download badge, a
/// duration and an ellipsis menu — `SongRow`'s `trailing` parameter replaces the
/// menu but keeps the other two. Between the system's selection circle inset on
/// the left and its reorder grip on the right, those left almost no width for
/// the title. Apple Music's editor rows carry the same three fields and no
/// controls of their own.
///
/// Dropping `SongRow` also drops two things that do not belong in a list being
/// dragged: a per-row `DownloadManager` observation (one per visible row, all
/// re-rendering on any song's download progress) and a long-press context menu,
/// which competes with the drag gesture.
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

/// One row of an edit session.
///
/// Identity is a per-session `UUID` rather than the song ID or the row offset,
/// because neither survives editing: a playlist may legitimately hold the same
/// song twice (so song IDs are not unique), and offsets change under every move
/// (so a selection keyed on them would follow the position instead of the row).
/// A UUID minted once when the session opens is stable across both.
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

/// Apple Music's playlist editor: selection circles on the left for a
/// multi-select delete, reorder grips on the right for drag-to-reorder.
///
/// Both affordances are the system's, not hand-rolled — a `List` in
/// `editMode == .active` with an `onMove` draws them, and gets autoscroll at the
/// edges, VoiceOver's "reorder" rotor and the lift/drop animations for free.
/// That is also why this is a separate screen rather than a mode inside
/// `PlaylistDetailView`: that view's `ScrollView` carries a parallax hero, a
/// pull-to-reveal search field and scroll-geometry-driven nav-bar tracking, none
/// of which survive being restructured into a `List`.
struct PlaylistEditView: View {
    let playlistName: String
    let target: PlaylistEditTarget
    /// Handed the final order so the detail screen can adopt it without waiting
    /// for a refetch.
    let onFinish: ([Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var songs: [EditableSong]
    @State private var selection: Set<UUID> = []
    @State private var failureMessage: String?
    @State private var isAddingSongs = false
    @State private var isFinishing = false
    /// Set when a write fails, to stop queued work that was computed against
    /// the now-rolled-back list. Cleared when the error is dismissed.
    @State private var queueFailed = false
    /// Serialises the writes. Two moves dropped in quick succession would
    /// otherwise race, and the server applies them one membership at a time —
    /// the second must be computed against the list the first produced.
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
            // No `onDelete`. Multi-select already deletes a single row, and the
            // swipe competed with the drag: both start as a horizontal-ish pan
            // on a row that is also a drag source.
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Unconditionally active: this screen exists only to edit, so there is
        // no non-editing state to toggle into.
        .environment(\.editMode, .constant(.active))
        .musicScreenBackground()
        .navigationTitle(playlistName)
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : AppMotion.quick, value: songs)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isFinishing {
                    // Queued writes are still landing; see `finish()`.
                    ProgressView()
                } else {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("PlaylistEdit.done")
                }
            }
        }
        // `safeAreaBar`, not a `.bottomBar` toolbar — the same choice
        // `AddToPlaylistSheet` makes, and for a second reason here: a
        // `.bottomBar` toolbar inside this presented `NavigationStack` made
        // UIKit log "Adding 'UIKitToolbar' as a subview of
        // UIHostingController.view is not supported" on every appearance.
        //
        // Trash hard left, plus hard right, nothing in between — Apple Music's
        // editor bar. The `Spacer` is what pins them to the edges.
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
                // The add route appends, so mirror that locally rather than
                // refetching — the editor's order is the one being edited.
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
                        // List and server agree again, so the queue can reopen.
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
        // Deliberately no `onDisappear { pendingWork?.cancel() }`.
        //
        // This screen is presented full-screen, so Done is the only way out —
        // and Done used to dismiss immediately, letting `onDisappear` cancel a
        // reorder that had not finished being written. That lost the user's
        // edit while showing it as applied. `finish()` now waits for the queue
        // instead, and the writes are short enough that letting a torn-down
        // session's last request complete is better than dropping it.
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

    /// Waits for queued writes before handing the list back.
    ///
    /// Dismissing immediately raced the write queue: the screen would close
    /// with a reorder still in flight, and tearing the session down cancelled
    /// it — the edit looked applied and silently was not.
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

    /// Applies the move locally first so the row settles under the finger, then
    /// writes the settled order through.
    ///
    /// The list is read *after* `move(fromOffsets:toOffset:)` rather than from
    /// `destination`, which is a pre-removal offset and so is off by the number
    /// of rows lifted from above it. Sending the settled array sidesteps that
    /// arithmetic entirely, and covers a multi-row move for free.
    private func move(from source: IndexSet, to destination: Int) {
        let previous = songs
        var updated = songs
        updated.move(fromOffsets: source, toOffset: destination)
        songs = updated
        AppHaptic.grab.play()

        enqueue { [previous, updated] in
            // The settled list is replayed as single moves, one per position
            // that disagrees, walking left to right so each step fixes one slot
            // without disturbing an earlier one. An ordinary one-row drag is a
            // single call.
            //
            // `newOrder` is an `order` *value*, not a row position. Verified
            // against the API: sending 12 gave the song `order: 12` and placed
            // it above the song that held that value, not at row 12. So a
            // destination is expressed as the value of whoever currently holds
            // the slot; the server assigns it and shifts the rest.
            //
            // On a densely numbered list this is exact in every direction, and
            // stays dense — measured over consecutive drags to the top, the
            // bottom and the middle, with no ties produced.
            //
            // A list carrying *duplicate* values is the one case this cannot
            // place into: no integer sits between two songs sharing a value, so
            // the slot between them is unreachable and a drop there lands
            // beside it. Retrying makes it worse rather than better — it just
            // alternates between the two neighbouring slots — so it is left to
            // land adjacent, and `resync` makes sure the screen then shows
            // where the song really is rather than where it was dropped.
            let targetRows = updated.map(\.id)
            // Server-side truth, which is still `previous` until a write lands.
            //
            // Deliberately *not* `songs`: that already holds the optimistic
            // post-drag arrangement by this point, so comparing against it
            // finds every row already in place and sends nothing at all — the
            // drag then appears to work and silently reverts on the next fetch.
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
                // Each move renumbers part of the list, so the next step reads
                // the server's values rather than assuming what they became.
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
            // Put back only what actually failed, each at the index it held
            // before the delete, so a partial failure doesn't reshuffle the
            // rows that did come out.
            var restored = songs
            let failedIDs = Set(failed.map(\.id))
            for item in previous where failedIDs.contains(item.id) {
                let originalIndex = previous.firstIndex(of: item) ?? restored.count
                restored.insert(item, at: min(originalIndex, restored.count))
            }
            songs = restored
            // Whatever *did* come out shifted the survivors, so take the
            // server's word for where things are before reporting the failure.
            await resync()
            failureMessage = failed.count == 1
                ? String(localized: "\(failed[0].song.title) couldn't be removed. Check your connection and try again.")
                : String(localized: "\(failed.count) songs couldn't be removed. Check your connection and try again.")
        }
    }

    /// Adopts the server's ordering after a mutation.
    ///
    /// Moves are computed from each song's `order`, so those values have to be
    /// the server's real ones. They cannot be predicted: the server renumbers
    /// only the range a move touches and leaves ties and gaps elsewhere intact
    /// — a 20-song playlist sat at `0…12` densely while rows below it stayed
    /// tied on 13 and 18. Deriving them from row positions instead was wrong
    /// wherever the numbering was not dense, which is exactly where reordering
    /// was already hardest.
    ///
    /// Costs one read per drop, which is worth it for values every subsequent
    /// move depends on. Row identity is carried across by pairing on song ID so
    /// the `List` does not treat resynced rows as new ones, and so a selection
    /// survives a reorder.
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

    /// Chains onto the previous write instead of racing it.
    ///
    /// A failed step stops the queue. Every step computes from the list its
    /// predecessor left behind, so once a failure has rolled the list back,
    /// anything still queued is working from a state that no longer exists and
    /// would write nonsense. The queue reopens when the user dismisses the
    /// error, by which point the list and the server agree again.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previousWork = pendingWork
        pendingWork = Task { @MainActor in
            _ = await previousWork?.result
            guard !Task.isCancelled, !queueFailed else { return }
            await work()
        }
    }
}
