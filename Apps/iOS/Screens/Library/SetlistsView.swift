import SwiftUI

/// Every karaoke stream's setlist, newest first, filtered by year from the
/// toolbar and by search.
struct SetlistsView: View {
    @Namespace private var zoomNamespace
    @State private var viewModel = SetlistsViewModel()
    @State private var searchText = ""

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only the unfiltered list leads with the latest stream.
    private var showsLatest: Bool {
        viewModel.filter.year == nil && trimmedQuery.isEmpty
    }

    private var yearTitle: String {
        viewModel.filter.year.map { String($0) } ?? String(localized: "All Years")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsLatest, let latest = viewModel.latest {
                    SetlistLatestCard(setlist: latest, zoomNamespace: zoomNamespace)
                        .padding(.horizontal, AM.Spacing.screenMargin)
                        .padding(.bottom, AM.Spacing.xl)
                }
                content
            }
            .frame(maxWidth: AM.Layout.wideRailMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AM.Spacing.m)
        }
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Karaoke Setlists")
        // Inline for the same reason as PlaylistListView: a large title
        // bounces when a zoom push leaves this screen on display.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.years.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { yearMenu }
            }
        }
        .searchable(text: $searchText, prompt: "Search Setlists")
        .secondarySearchBehavior()
        .refreshableWithTick { await viewModel.refresh() }
        .onAppear { viewModel.loadIfNeeded() }
        .task(id: trimmedQuery) {
            await viewModel.search(trimmedQuery)
        }
    }

    @ViewBuilder private var content: some View {
        if viewModel.setlists.isEmpty {
            if viewModel.isLoading {
                CenteredLoadingView(minHeight: 360, label: String(localized: "Loading setlists"))
            } else if viewModel.loadFailed {
                VStack(spacing: AM.Spacing.l) {
                    MusicEmptyState(
                        title: String(localized: "Couldn't Load Setlists"),
                        message: String(localized: "Check your connection and try again.")
                    )
                    MusicEmptyActionButton(title: String(localized: "Try Again")) {
                        viewModel.retry()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                let isFiltered = viewModel.filter != SetlistsViewModel.Filter()
                MusicEmptyState(
                    title: isFiltered ? String(localized: "No Results") : String(localized: "No Setlists"),
                    message: isFiltered
                        ? String(localized: "Try another name or year.")
                        : String(localized: "Setlists will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        } else {
            AMSectionHeader(yearTitle)
                .padding(.bottom, AM.Spacing.sectionHeaderGap)
            ForEach(viewModel.setlists) { setlist in
                row(setlist)
            }
            if viewModel.isLoadingMore {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AM.Spacing.m)
            }
        }
    }

    private func row(_ setlist: KaraokeSetlist) -> some View {
        ZoomNavigationLink(id: setlist.id, in: zoomNamespace) {
            PlaylistDetailView(playlist: setlist.playlist)
        } label: {
            SetlistRow(setlist: setlist)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
        .accessibilityIdentifier("Setlists.row.\(setlist.id)")
        .contextMenu {
            PlaylistActionsMenuItems(playlist: setlist.playlist, songs: setlist.songs)
        } preview: {
            PlaylistContextPreview(playlist: setlist.playlist)
        }
        .onAppear { viewModel.loadMoreIfNeeded(current: setlist) }
    }

    private var yearMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { viewModel.filter.year },
                set: { year in
                    AppHaptic.selection.play()
                    viewModel.selectYear(year)
                }
            )) {
                Text("All Years").tag(Int?.none)
                ForEach(viewModel.years, id: \.self) { year in
                    Text(verbatim: String(year)).tag(Int?.some(year))
                }
            } label: {
                Text("Year")
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                "Year",
                systemImage: viewModel.filter.year == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .accessibilityIdentifier("Setlists.yearMenu")
        .accessibilityValue(yearTitle)
    }
}

private extension KaraokeSetlist {
    /// The songs in the order they were sung; decoding sorts them.
    var songs: [Song] {
        playlist.songListDTOs ?? []
    }
}

/// What the latest-stream card's Play and Shuffle buttons do. Tests pass their
/// own playback functions to see what each button hands over.
@MainActor
enum SetlistCardActions {
    static func play(
        _ setlist: KaraokeSetlist,
        playInOrder: @MainActor (Song, Playlist, [Song]) -> Void = PlaylistPlayback.playInOrder
    ) {
        let songs = setlist.songs
        guard let first = songs.first else { return }
        playInOrder(first, setlist.playlist, songs)
    }

    static func shuffle(
        _ setlist: KaraokeSetlist,
        playShuffled: @MainActor (Playlist, [Song]) -> Void = PlaylistPlayback.playShuffled
    ) {
        playShuffled(setlist.playlist, setlist.songs)
    }
}

/// "15 songs · 53 min", or just the count when the length is unknown.
private struct SetlistDetailsText: View {
    let setlist: KaraokeSetlist

    var body: some View {
        let count = setlist.playlist.songCountText
        if let seconds = setlist.totalDuration, seconds > 0 {
            let length = Text(.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
            Text("\(count) · \(length)")
        } else {
            Text(verbatim: count)
        }
    }
}

private struct SetlistRow: View {
    let setlist: KaraokeSetlist
    private let size = SongRowSize.regular

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            PlaylistArtwork(playlist: setlist.playlist, cornerRadius: size.cornerRadius)
                .frame(width: size.artSize, height: size.artSize)
                .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(setlist.name)
                    .font(AM.Font.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                SetlistDetailsText(setlist: setlist)
                    .font(AM.Font.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AM.Font.chevron)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.vertical, AM.Spacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The latest stream's setlist, with Play and Shuffle.
private struct SetlistLatestCard: View {
    let setlist: KaraokeSetlist
    let zoomNamespace: Namespace.ID

    var body: some View {
        let songs = setlist.songs
        VStack(alignment: .leading, spacing: AM.Spacing.l) {
            // Its own zoom id: the same setlist is usually also the first row.
            ZoomNavigationLink(id: "latest.\(setlist.id)", in: zoomNamespace) {
                PlaylistDetailView(playlist: setlist.playlist)
            } label: {
                HStack(spacing: AM.Spacing.l) {
                    PlaylistArtwork(playlist: setlist.playlist, cornerRadius: AM.Radius.card)
                        .frame(width: AM.Spacing.compactShelfTile, height: AM.Spacing.compactShelfTile)
                        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
                    VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                        Text("Latest Stream")
                            .font(AM.Font.eyebrow)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(setlist.name)
                            .font(AM.Font.groupHeader)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        SetlistDetailsText(setlist: setlist)
                            .font(AM.Font.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.85, haptic: .selection))
            .accessibilityIdentifier("Setlists.latest")

            HStack(spacing: AM.Spacing.m) {
                Button {
                    AppHaptic.selection.play()
                    SetlistCardActions.play(setlist)
                } label: {
                    LibraryActionButtonLabel(symbol: "play.fill", text: String(localized: "Play"))
                }
                .disabled(songs.isEmpty)
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))

                Button {
                    AppHaptic.selection.play()
                    SetlistCardActions.shuffle(setlist)
                } label: {
                    LibraryActionButtonLabel(symbol: "shuffle", text: String(localized: "Shuffle"))
                }
                .disabled(songs.isEmpty)
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            }
        }
        .padding(AM.Spacing.l)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous)
                .strokeBorder(Color.appDivider.opacity(0.7), lineWidth: 0.7)
        }
    }
}
