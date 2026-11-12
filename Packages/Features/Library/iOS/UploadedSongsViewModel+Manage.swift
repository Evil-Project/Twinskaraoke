import Foundation

/// Editing and deleting the user's own uploads.
extension UploadedSongsViewModel {
    struct ManageService {
        var update: @MainActor (_ id: String, _ edit: UploadedSongEdit) async throws -> Void
        var delete: @MainActor (_ id: String) async throws -> Void
        /// Drops the song's offline copy, and stops a download of it that is
        /// queued or running.
        var removeDownload: @MainActor (_ id: String) -> Void

        static var live: ManageService {
            ManageService(
                update: { id, edit in try await KaraokeAPIClient.updateUploadedSong(id: id, edit: edit) },
                delete: { id in try await KaraokeAPIClient.deleteUploadedSong(id: id) },
                removeDownload: { id in
                    let downloads = DownloadManager.shared
                    guard hasOfflineWork(downloads.status(for: id)) else { return }
                    // Cancels queued and running work as well as removing files.
                    downloads.remove(songID: id)
                }
            )
        }

        /// Whether a deleted song has anything in Downloads: a finished copy,
        /// or a download that is queued or running and would otherwise
        /// finish after the delete and keep the song there.
        nonisolated static func hasOfflineWork(_ status: SongDownloadStatus) -> Bool {
            status.isDownloaded || status.isDownloading
        }

        /// Accepts every edit and delete without a request, for UI tests
        /// launched with `-UITestMode`.
        static var uiTestFixture: ManageService {
            ManageService(
                update: { _, _ in try await Task.sleep(for: .milliseconds(300)) },
                delete: { _ in try await Task.sleep(for: .milliseconds(300)) },
                removeDownload: { _ in }
            )
        }
    }

    enum EditOutcome: Equatable {
        case saved
        /// Nothing differed from the song, so nothing was sent.
        case unchanged
        /// The server would store a blank title, so it isn't sent.
        case emptyTitle
        case failed(SongUploadFailure)
    }

    /// The artist a song's edit form starts with: its original artist text,
    /// which is the one string the server stores for an upload.
    nonisolated static func artistText(for song: Song) -> String {
        (song.originalArtists ?? []).joined(separator: ", ")
    }

    /// The fields the edit form shows, as the server names them.
    nonisolated static let editFields = ["Title", "Artist"]

    /// The message the edit form shows apart from its fields' own: the
    /// failure's, unless the server's field errors name a field the form
    /// shows, whose footer then says it. An error for any other field would
    /// otherwise leave the form silent.
    static func generalEditMessage(for failure: SongUploadFailure?) -> String? {
        guard let failure else { return nil }
        if case let .server(_, problem?) = failure,
           editFields.contains(where: { problem.message(forField: $0) != nil })
        {
            return nil
        }
        return failure.userMessage
    }

    /// `edit` with its fields trimmed.
    nonisolated static func trimmed(_ edit: UploadedSongEdit) -> UploadedSongEdit {
        UploadedSongEdit(
            title: edit.title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: edit.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Whether the trimmed `edit` leaves `song` as it is.
    nonisolated static func isUnchanged(_ edit: UploadedSongEdit, for song: Song) -> Bool {
        trimmed(edit) == UploadedSongEdit(title: song.title, artist: artistText(for: song))
    }

    /// Saves a new title and artist, shows them on the row at once, then
    /// reloads the list from the server, which is the only source of how it
    /// stored them. A failed reload leaves the updated row.
    func update(_ song: Song, edit: UploadedSongEdit) async -> EditOutcome {
        let edit = Self.trimmed(edit)
        guard !edit.title.isEmpty else { return .emptyTitle }
        guard !Self.isUnchanged(edit, for: song) else { return .unchanged }
        do {
            try await manage.update(song.id, edit)
        } catch {
            return .failed(error as? SongUploadFailure ?? .unknown)
        }
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index] = Self.applying(edit, to: songs[index])
            rebuildDisplayedSongs()
        }
        await refresh()
        return .saved
    }

    /// `song` with the title and artist of a saved `edit`. The server keeps
    /// the artist as one string, which `artistText(for:)` reads back.
    nonisolated static func applying(_ edit: UploadedSongEdit, to song: Song) -> Song {
        Song(
            id: song.id,
            title: edit.title,
            duration: song.duration,
            absolutePath: song.absolutePath,
            cloudflareID: song.cloudflareID,
            coverArt: song.coverArt,
            originalArtists: edit.artist.isEmpty ? [] : [edit.artist],
            coverArtists: song.coverArtists,
            userUploaded: song.userUploaded,
            oss: song.oss,
            order: song.order
        )
    }

    /// Removes the row at once and deletes the song on the server; on
    /// success its offline copy goes too. A failed delete puts the row back
    /// where it was and returns why. The playback queue is left alone.
    func delete(_ song: Song) async -> SongUploadFailure? {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return nil }
        songs.remove(at: index)
        rebuildDisplayedSongs()
        do {
            try await manage.delete(song.id)
        } catch {
            // A reload while the request ran may already have the row back.
            if !songs.contains(where: { $0.id == song.id }) {
                songs.insert(song, at: min(index, songs.count))
                rebuildDisplayedSongs()
            }
            return error as? SongUploadFailure ?? .unknown
        }
        // Every load from here on leaves it out, including one that started
        // before the delete and finishes after it.
        deletedSongIDs.insert(song.id)
        // A reload while the request ran may have put the row back.
        if songs.contains(where: { $0.id == song.id }) {
            songs.removeAll { $0.id == song.id }
            rebuildDisplayedSongs()
        }
        manage.removeDownload(song.id)
        return nil
    }
}
