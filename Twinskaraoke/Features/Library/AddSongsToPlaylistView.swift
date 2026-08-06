import SwiftUI

/// The playlist editor's "+" destination: search the catalogue and add songs to
/// the collection being edited.
///
/// The inverse of `AddToPlaylistSheet`, which starts from one song and picks a
/// playlist. Here the playlist is fixed and the songs are what vary, so the two
/// share a look but not a structure.
struct AddSongsToPlaylistView: View {
    let target: PlaylistEditTarget
    /// Songs already in the collection, so they can be shown as present rather
    /// than offered again. Includes anything added during this session.
    let existingSongIDs: Set<String>
    /// Handed the songs that were actually accepted by the server, so the
    /// editor can append them without refetching.
    let onFinish: ([Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var inFlight: Set<String> = []
    @State private var added: [Song] = []
    @State private var failed: Set<String> = []
    /// `onDisappear` can fire more than once for a single dismissal; without
    /// this the editor would append the same songs twice.
    @State private var hasReported = false

    private var addedIDs: Set<String> { Set(added.map(\.id)) }

    var body: some View {
        NavigationStack {
            content
                .musicScreenBackground()
                .navigationTitle("Add Songs")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search songs")
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { finish() }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("AddSongs.done")
                    }
                }
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }
                // Completion hangs off dismissal, not off the Done button.
                //
                // This is a sheet, so it can also be swiped away — and songs
                // added before that swipe are already on the server. Reporting
                // them only from Done meant a swipe-dismiss left the editor
                // showing a list that was missing them, which it would then
                // hand back to the detail screen as if authoritative.
                .onDisappear {
                    searchTask?.cancel()
                    guard !hasReported else { return }
                    hasReported = true
                    onFinish(added)
                }
                // Additions are in flight; leaving now would drop them from the
                // report even though the server is applying them.
                .interactiveDismissDisabled(!inFlight.isEmpty)
                .animation(reduceMotion ? nil : AppMotion.quick, value: results)
                .animation(reduceMotion ? nil : AppMotion.snap, value: inFlight)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching, results.isEmpty {
            CenteredLoadingView(label: "Searching songs")
        } else if results.isEmpty {
            MusicEmptyState(
                title: hasSearched ? String(localized: "No Results") : String(localized: "Find Songs"),
                message: hasSearched
                    ? String(localized: "Try another song title or artist.")
                    : String(localized: "Search for songs to add to this playlist.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            List(results) { song in
                row(for: song)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AM.Spacing.screenMargin,
                        bottom: 0,
                        trailing: AM.Spacing.screenMargin
                    ))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func row(for song: Song) -> some View {
        let isPresent = existingSongIDs.contains(song.id) || addedIDs.contains(song.id)
        // The same lean row the editor uses. `PlaylistRow` brings its own
        // ellipsis menu, which sat next to the add button as a second trailing
        // control and crowded the title out.
        return HStack(spacing: 12) {
            PlaylistEditSongRow(song: song)
            Spacer(minLength: 8)
            Button {
                add(song)
            } label: {
                statusIcon(isPresent: isPresent, isAdding: inFlight.contains(song.id), hasFailed: failed.contains(song.id))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isPresent || inFlight.contains(song.id))
            .accessibilityLabel(isPresent ? "Already added" : "Add \(song.title)")
        }
    }

    @ViewBuilder
    private func statusIcon(isPresent: Bool, isAdding: Bool, hasFailed: Bool) -> some View {
        if isAdding {
            ProgressView().controlSize(.regular)
        } else if isPresent {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
        } else if hasFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(Color.appAccent)
        } else {
            Image(systemName: "plus.circle")
                .font(.title3.bold())
                .foregroundStyle(Color.appAccent)
        }
    }

    /// Only dismisses — `onDisappear` is the single completion path, so Done
    /// and a swipe report the same thing exactly once.
    private func finish() {
        AppHaptic.commit.play()
        dismiss()
    }

    /// Debounced so typing doesn't fire a request per keystroke.
    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = (try? await KaraokeAPIClient.searchSongs(query: trimmed, pageSize: 50)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            hasSearched = true
            isSearching = false
        }
    }

    private func add(_ song: Song) {
        guard !inFlight.contains(song.id), !addedIDs.contains(song.id) else { return }
        inFlight.insert(song.id)
        failed.remove(song.id)
        Task { @MainActor in
            let ok = await target.add(songID: song.id)
            inFlight.remove(song.id)
            if ok {
                AppHaptic.success.play()
                added.append(song)
            } else {
                AppHaptic.error.play()
                failed.insert(song.id)
            }
        }
    }
}
