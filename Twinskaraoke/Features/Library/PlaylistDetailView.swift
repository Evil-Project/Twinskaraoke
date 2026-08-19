import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var loader = PlaylistDetailViewModel()
    private let favorites = FavoritesManager.shared
    // Rows derive artwork URLs through `Song`, which consults the fallback
    // pool; reading the revision in `body` re-renders them when it changes.
    private let fallbackArt = FallbackArtRevision.shared
    @State private var searchText = ""
    @State private var contentWidth: CGFloat = 390
    @FocusState private var isSearchFocused: Bool
    /// Height of `playlistSearchField` — 40pt capsule plus its bottom padding.
    /// The scroll view starts exactly this far down, so the field sits just off
    /// the top of the viewport and a pull brings it into view.
    private static let searchFieldExtent: CGFloat = 52
    /// How far the list must be scrolled down before the field is put away.
    private static let searchDismissDistance: CGFloat = 40
    /// Incidental overscroll below this reveals nothing at all.
    private static let searchRevealDeadZone: CGFloat = 30
    /// Below 1 so the field trails the finger — ~110pt of pull for a full reveal.
    private static let searchRevealResistance: CGFloat = 0.65
    /// Step the observed pull is rounded to, so the reveal cannot re-trigger the
    /// scroll observation that drives it. See the `onScrollGeometryChange` below.
    private static let searchPullStep: CGFloat = 2
    @State private var searchRevealHeight: CGFloat = 0
    /// Drives the navigation bar's title and background. The old search field
    /// hid the title while it was active, because it lived in the bar area; the
    /// pull-revealed field is content, so the title only follows the scroll.
    @State private var showsCollapsedTitle = false
    /// Latched once the pull completes, so the field stays put instead of
    /// collapsing the moment the finger lifts.
    @State private var isSearchLatched = false

    private static let searchAnchor = "playlist.search"
    private static let contentAnchor = "playlist.content"
    @State private var filteredSongs: [Song]
    @State private var filterTask: Task<Void, Never>?
    @State private var favoritesRefreshTask: Task<Void, Never>?
    @State private var prefetchedIDs: [String] = []
    @State private var prefetchTask: Task<Void, Never>?
    @State private var removalErrorSong: Song?
    @State private var isEditing = false
    /// Everything that starts playback — song rows *and* Play/Shuffle — ignores
    /// touches until the push has settled. The zoom transition does not gate
    /// input, so a second tap aimed at the grid tile lands on this screen as it
    /// arrives under the finger, and at that Y coordinate there is either a song
    /// row or an action button. Both started playing; the buttons were exempt
    /// from this gate until they were caught doing it. Scrolling and Back stay
    /// live throughout.
    ///
    /// Two conditions, because neither covers the other: the transition itself
    /// says when the zoom is done (measured at ~0.9s, far longer than the delay
    /// below used to allow), and the delay covers the arrivals that have no
    /// transition to ask — reduce motion, or coming back from a sub-screen.
    @Environment(\.zoomPushIsArriving) private var isArriving
    @State private var hasSettledAfterAppear = false
    @State private var rowArmingTask: Task<Void, Never>?
    private var playbackTapsArmed: Bool { hasSettledAfterAppear && !isArriving }
    /// onAppear fires repeatedly for one visit — device logs show appeared and
    /// disappeared 1ms apart, over and over. Reloading below cancels and restarts
    /// the network load, so it remains one-shot work for a visit.
    @State private var hasStartedVisit = false
    private let userPlaylists = UserPlaylistsManager.shared

    init(playlist: Playlist) {
        self.playlist = playlist
        // searchText starts empty, so the initial filtered list is the fallback.
        _filteredSongs = State(initialValue: playlist.songListDTOs ?? [])
    }

    private var playlistSearchField: some View {
        HStack(spacing: AM.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Playlist", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("PlaylistDetail.searchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .appGlassBackground(in: Capsule())
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.bottom, AM.Spacing.m)
        .accessibilityIdentifier("PlaylistDetail.search")
    }

    /// Grows the field with the pull, latches it open once fully revealed, and
    /// drops it again when the list is scrolled back down.
    private func updateSearchReveal(pull: CGFloat) {
        let extent = Self.searchFieldExtent
        if isSearchLatched {
            // Scrolling down past the top puts it away again.
            if pull < -Self.searchDismissDistance, !isSearchFocused, searchText.isEmpty {
                isSearchLatched = false
                withOptionalAnimation(reduceMotion ? nil : AppMotion.quick) {
                    searchRevealHeight = 0
                }
            } else if searchRevealHeight != extent {
                searchRevealHeight = extent
            }
            return
        }

        // Deliberately resistant. Tracking the pull 1:1 from the first pixel made
        // the field appear during ordinary scrolling; it should take a decided
        // pull. The dead zone absorbs incidental overscroll, and the resistance
        // means the field moves slower than the finger, so a full reveal needs
        // roughly `deadZone + extent / resistance` points of travel.
        let effective = max(0, pull - Self.searchRevealDeadZone) * Self.searchRevealResistance
        let revealed = min(effective, extent)
        if revealed >= extent {
            isSearchLatched = true
            AppHaptic.boundary.play()
            withOptionalAnimation(reduceMotion ? nil : AppMotion.snap) {
                searchRevealHeight = extent
            }
        } else if searchRevealHeight != revealed {
            searchRevealHeight = revealed
        }
    }

    /// Held back until the transition has run: warmCollection derives a URL for
    /// every song, and doing that inside the transition window competes with the
    /// animation.
    ///
    /// The list is read when the task fires, not when it is scheduled. Capturing
    /// `displayedSongs` from `body` snapshotted the `songListDTOs` fallback,
    /// because `loader.songs` is still nil at that point — so if the fetch landed
    /// inside the delay, this overwrote the authoritative warm with the stale one
    /// under the same reason key, and clobbered `prefetchedIDs` with it.
    private func schedulePrefetch() {
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let songs = loader.songs ?? playlist.songListDTOs ?? []
            guard !songs.isEmpty else { return }
            prefetchedIDs = Array(songs.prefix(18)).map(\.id)
            prefetchArtwork(songs: songs)
        }
    }

    private func usesWideOverview(availableWidth: CGFloat) -> Bool {
        AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        )
    }


    var body: some View {
        detailContent
            // A cover, not a push. Pushed, the editor's bottom bar sits behind
            // the tab bar, and hiding that is not enough on its own: the
            // LNPopup mini player merges into the tab bar's metrics and would
            // still float over the Delete button. A full-screen presentation is
            // above both, which is also where Apple Music puts its editor.
            .fullScreenCover(isPresented: $isEditing) {
                if let editTarget {
                    NavigationStack {
                        PlaylistEditView(
                            playlistName: playlist.name,
                            songs: loader.songs ?? playlist.songListDTOs ?? [],
                            target: editTarget
                        ) { reordered in
                            // Adopt the edited order straight away. The detail
                            // route now returns it too — `saveSongOrder`
                            // invalidates that cache — but refetching to learn
                            // what we just did would flash the old order first.
                            loader.songs = reordered
                        }
                    }
                }
            }
    }

    /// Non-nil only where editing can actually be written through: Favorites,
    /// which owns its own order, or a playlist the signed-in user owns.
    ///
    /// Ownership is membership in `/api/user/playlists` for the same reason
    /// `songRemovalContext` uses it — see the note there. `editable`/`deletable`
    /// come back false on playlists the user created, and `isPersonal` is false
    /// on the instance that reaches this screen.
    private var editTarget: PlaylistEditTarget? {
        if playlist.isFavorites { return .favorites }
        guard userPlaylists.playlists.contains(where: { $0.id == playlist.id }) else {
            return nil
        }
        return .playlist(id: playlist.id)
    }

    /// Spelled out as its own property with an explicit type on purpose. Inline
    /// in the toolbar, the `nil`-or-closure ternary had to be resolved as part
    /// of the `detailContent` chain, which was already close enough to the
    /// type-checker's budget that the extra overload resolution tipped it over.
    private var editAction: (() -> Void)? {
        // Gated on an authoritative list, not just a target.
        //
        // The editor is seeded with a snapshot and hands its result back to
        // `loader.songs` on finish. Opening it before the fetch lands would
        // seed it from the `songListDTOs` fallback — or from nothing at all —
        // and closing it would then overwrite a newer, complete list with that
        // stale snapshot, or with an empty one.
        guard editTarget != nil, loader.hasAuthoritativeSongs else { return nil }
        return beginEditing
    }

    private func beginEditing() {
        // The web client refuses to reorder under an active filter, and for the
        // same reason: the indices the endpoint takes are positions in the whole
        // playlist, so dragging within a filtered subset would write the wrong
        // ones. Clearing the query sidesteps it rather than blocking the action.
        searchText = ""
        filteredSongs = loader.songs ?? playlist.songListDTOs ?? []
        isSearchFocused = false
        AppHaptic.selection.play()
        isEditing = true
    }

    // @ViewBuilder is load-bearing, not decoration: `View.body` declares it
    // implicitly, so extracting this out of `body` dropped it and turned the
    // leading `let _ =` into a multi-statement closure the compiler had to infer
    // as a whole — which it cannot do in reasonable time for an expression this
    // size ("unable to type-check this expression in reasonable time").
    @ViewBuilder
    private var detailContent: some View {
        let _ = fallbackArt.revision
        let songs: [Song] = loader.songs ?? playlist.songListDTOs ?? []
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Derive the unfiltered list rather than mirroring it into @State.
        //
        // `filteredSongs` is only meaningful while a search is active. Using it
        // as the sole source made the whole screen depend on a sync that had no
        // way to self-correct: if it was ever missed, the list stayed empty and
        // stayed empty. See the `onChange(of: loader.songs)` note below.
        let displayedSongs = isSearching ? filteredSongs : songs
        // The ScrollView is a *direct* child of the navigation container, not
        // wrapped in a GeometryReader.
        //
        // The wrapper broke the navigation bar's scroll-edge tracking, so it
        // could not collapse the large title or tuck the search drawer away —
        // the drawer sat pinned open instead of starting hidden and revealing on
        // a pull, which is the whole behaviour we are after. Width is measured
        // from the content instead, which needs no wrapper.
        ScrollView {
            VStack(spacing: 0) {
                // Above the content, not in the navigation bar, and revealed by
                // ordinary scrolling rather than a gesture.
                //
                // The nav-bar drawer cannot do what we want: with
                // `hidesSearchBarWhenScrolling` it is *visible at scroll top* by
                // definition and hides as you scroll down — the opposite of
                // hidden-until-pulled. And the hand-rolled version this replaces
                // read raw overscroll, which is the same drag the zoom uses to
                // dismiss, so the two fought and the dismissal won.
                //
                // As the first row of content it is neither: `scrollTo` below
                // parks the view just underneath it on appear, so pulling down
                // simply scrolls it into view. No gesture, nothing to arbitrate.
                playlistSearchField
                    .frame(height: searchRevealHeight, alignment: .bottom)
                    .opacity(searchRevealHeight / Self.searchFieldExtent)
                    .clipped()
                    // Neither opacity nor clipping removes a view from the
                    // accessibility tree, so while collapsed the field could
                    // still take VoiceOver or hardware-keyboard focus and raise
                    // the keyboard with nothing visible to type into.
                    .allowsHitTesting(searchRevealHeight > 0)
                    .accessibilityHidden(searchRevealHeight <= 0)
                    // Above the hero regardless of what its visual effect does.
                    .zIndex(1)
                    .id(Self.searchAnchor)
                playlistScrollContent(
                    songs: songs,
                    displayedSongs: displayedSongs,
                    isSearching: isSearching,
                    width: contentWidth
                )
                .id(Self.contentAnchor)
            }
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    guard width > 0, abs(width - contentWidth) > 0.5 else { return }
                    contentWidth = width
                }
                // Row changes (e.g. unfavouriting) used to animate via the
                // `filteredSongs` swap; now that the list is derived, the
                // animation attaches to the value instead. Same 300-row
                // guard: animating a large structural swap stalls the main
                // thread.
                .animation(
                    reduceMotion || displayedSongs.count >= 300
                        ? nil
                        : AppMotion.quick,
                    value: displayedSongs
                )
        }
        .smoothScrolling()
        .scrollEdgeHaptic()
        .scrollDismissesKeyboard(.interactively)
        // Resting offset expressed as a raw point, which is what finally worked.
        //
        // Four earlier attempts all failed for the same underlying reason — they
        // depended on something that is not ready at first layout:
        // `ScrollViewReader.scrollTo` from `onAppear` (no laid-out content to
        // scroll to), the same deferred past a yield (content not yet tall
        // enough to be scrollable), `scrollPosition(id:)` (needs the target row
        // measured), and before those the system nav-bar drawer, which is
        // visible at scroll top by definition and so can never start hidden.
        //
        // A raw offset needs none of that: it is just where the scroll view
        // starts, parking the search field exactly its own height above the
        // viewport.
        // Revealed by the pull itself, not by a resting scroll offset.
        //
        // Apple Music grows the field out of the overscroll: pull down, the
        // background stretches, and the search bar expands into the gap between
        // the toolbar and the title. Its height *is* the pull distance.
        //
        // Six attempts to instead park the scroll below a full-height field all
        // failed, for the same reason each time — they needed something that is
        // not settled at first layout (laid-out content, a measured row, or the
        // top inset, which is `-107` here rather than 0, so absolute offsets are
        // meaningless). Driving height from the live pull needs none of it.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Positive while pulled past the top.
            let pull = -(geometry.contentOffset.y + geometry.contentInsets.top)
            // Quantised, because this observation is circular: the action writes
            // `searchRevealHeight`, that height is laid out inside this very
            // scroll view, and the resulting geometry change re-enters here on
            // the same frame -- which is what SwiftUI reports as
            // "<OnScrollGeometryChange Modifier> tried to update multiple times
            // per frame". Rounding to a step gives the loop somewhere to stop:
            // the sub-step geometry the action induces no longer reads as a
            // change. `ScrollOptimization` makes the same point the coarse way,
            // with zones; a reveal needs to track the finger, so it rounds
            // instead. At 0.65 resistance a 2pt step is ~1.3pt of height.
            return (pull / Self.searchPullStep).rounded() * Self.searchPullStep
        } action: { _, pull in
            updateSearchReveal(pull: pull)
        }
        .scrollIndicators(.hidden)
        // Same threshold and wiring as BrowseSongCollectionView, ArtistsView and
        // DownloadedSongsView: the name belongs in the bar once its own heading
        // has scrolled away, and the bar stays transparent over the artwork until
        // then. Inline, never large — the zoom leaves the source screen on
        // display, so a large title collapsing on push is animated in full view.
        .collapsedNavigationTitle($showsCollapsedTitle)
        .musicScreenBackground()
        .navigationTitle(showsCollapsedTitle ? playlist.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .animation(
            reduceMotion ? nil : AppMotion.quick,
            value: showsCollapsedTitle
        )
        // Add to Library, Download / Remove Downloads and Refresh Playlist live
        // here and nowhere else on this screen. They were reachable only by
        // long-pressing the artwork between the pull-to-reveal search landing and
        // this — a context menu is a shortcut to actions, never their only home.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PlaylistMoreMenu(
                    playlist: playlist,
                    songs: songs,
                    onRefresh: refresh,
                    onEdit: editAction
                )
            }
        }
        .alert(
            "Couldn't Remove Song",
            isPresented: Binding(
                get: { removalErrorSong != nil },
                set: { if !$0 { removalErrorSong = nil } }
            ),
            presenting: removalErrorSong
        ) { _ in
            Button("OK", role: .cancel) { removalErrorSong = nil }
        } message: { song in
            Text("\(song.title) is still in \(playlist.name). Check your connection and try again.")
        }
        .onAppear {
            // Per-appear, deliberately outside the one-shot guard below.
            // onDisappear disarms the rows, so gating this on `hasStartedVisit`
            // left them permanently untappable after any re-appear — pushing a
            // sub-screen and coming back was enough.
            rowArmingTask?.cancel()
            rowArmingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                hasSettledAfterAppear = true
            }
            schedulePrefetch()

            guard !hasStartedVisit else { return }
            hasStartedVisit = true
            loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            // The removal menu item is gated on this list; without the warm-up
            // it stays hidden until something else happens to load it.
            userPlaylists.loadIfNeeded()
        }
        // Diffing on displayedSongs (Equatable) avoids allocating the prefix
        // id array on every body eval; it only builds when the list changes.
        .onChange(of: displayedSongs) { _, newSongs in
            let ids = Array(newSongs.prefix(18)).map(\.id)
            guard ids != prefetchedIDs else { return }
            prefetchedIDs = ids
            prefetchArtwork(songs: newSongs)
        }
        .onChange(of: searchText) { _, newValue in
            // Filtering a large playlist runs 3 localized comparisons per song;
            // debounce so typing doesn't stall the main thread per keystroke.
            filterTask?.cancel()
            filterTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                // Resolve the source list now, not at body-eval time, so a
                // loader.$songs update during the debounce isn't overwritten
                // by a filter of the stale snapshot.
                let currentSongs = loader.songs ?? playlist.songListDTOs ?? []
                filteredSongs = PlaylistSongSearch.filter(currentSongs, matching: newValue)
            }
        }
        // Keeps the *search* results fresh when the playlist reloads underneath
        // an active query. It deliberately no longer feeds the unfiltered list.
        //
        // This was `.onReceive(loader.$songs)`, and the two are not equivalent.
        // A `@Published` projected publisher replays its current value to every
        // new subscriber, so that fired on each appear and re-seeded the list
        // unconditionally. `onChange` fires neither on install nor when the new
        // value compares equal to the old. Both gaps bit: a playlist already
        // loaded when the view appeared never seeded, and Refresh re-fetched an
        // *equal* array, so nothing fired and the empty list could not recover
        // until the view was destroyed by popping back to Library.
        .onChange(of: loader.songs) { _, newSongs in
            let next = PlaylistSongSearch.filter(
                newSongs ?? playlist.songListDTOs ?? [],
                matching: searchText
            )
            // Animating a huge structural swap can stall the main thread;
            // only animate small list changes (e.g. unfavoriting a row).
            let canAnimate = filteredSongs.count < 300 && next.count < 300
            withOptionalAnimation(reduceMotion || !canAnimate ? nil : AppMotion.quick) {
                filteredSongs = next
            }
        }
        .onChange(of: favorites.favoriteIDs) { _, _ in
            guard playlist.isFavorites else { return }
            // Every star tap anywhere in the app fires this; coalesce rapid
            // toggles into a single refetch instead of reloading the whole
            // playlist per tap.
            favoritesRefreshTask?.cancel()
            favoritesRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            }
        }
        .onDisappear {
            rowArmingTask?.cancel()
            hasSettledAfterAppear = false
            prefetchTask?.cancel()
            // Same class of post-teardown work as the prefetches below:
            // favoritesRefreshTask starts a network fetch after a one-second
            // sleep, and filterTask writes state after 200ms.
            filterTask?.cancel()
            favoritesRefreshTask?.cancel()
            ArtworkPrefetcher.shared.cancel(reason: "playlist cover \(playlist.id)")
            ArtworkPrefetcher.shared.cancel(reason: "playlist songs \(playlist.id)")
            // prefetchArtwork starts three prefetches and this cancelled two of
            // them. The whole-playlist warm ran on regardless — hundreds of
            // images still downloading and decoding after the screen was gone,
            // and since each playlist warms under its own reason key, opening
            // several in a row stacked them instead of replacing them.
            ArtworkPrefetcher.shared.cancelWarm(reason: "playlist warm \(playlist.id)")
        }
    }

    @ViewBuilder
    private func playlistScrollContent(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        // No separate search-results mode. The custom reveal swapped the whole
        // screen for a bare list; the system drawer sits in the navigation bar
        // instead, so the hero and action buttons stay put and a query just
        // shortens the list underneath them — which is what Apple Music does.
        playlistOverview(
            songs: songs,
            displayedSongs: displayedSongs,
            isSearching: isSearching,
            width: width
        )
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.98))
        )
        .accessibilityIdentifier(isSearching ? "PlaylistDetail.SearchResults" : "PlaylistDetail.Overview")
    }

    private func refresh() {
        AppHaptic.selection.play()
        loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
    }

    private func prefetchArtwork(songs: [Song]) {
        ArtworkPrefetcher.shared.prefetchPlaylists(
            [playlist],
            limit: 6,
            reason: "playlist cover \(playlist.id)",
            variant: .thumbnail
        )
        ArtworkPrefetcher.shared.prefetchSongs(
            Array(songs.prefix(ArtworkPrefetcher.songWindow)),
            reason: "playlist songs \(playlist.id)",
            variant: .row
        )
        // The windowed prefetch above only stays just ahead of the visible
        // rows, which a fast flick outruns. Warm the *whole* playlist onto disk
        // as well, so a second visit scrolls with no placeholders at all.
        ArtworkPrefetcher.shared.warmCollection(
            songs: songs,
            reason: "playlist warm \(playlist.id)",
            variant: .row
        )
    }

    @ViewBuilder
    private func playlistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        if usesWideOverview(availableWidth: width) {
            widePlaylistOverview(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching
            )
        } else {
            compactPlaylistOverview(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching,
                width: width
            )
        }
    }

    private func compactPlaylistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 18) {
            parallaxHero(width: width)
                .contextMenu {
                    PlaylistActionsMenuItems(playlist: playlist, songs: songs)
                } preview: {
                    PlaylistDetailContextPreview(
                        playlist: playlist,
                        songs: songs,
                        coverURLs: playlistCoverURLs
                    )
                }
            playlistTitleBlock(alignment: .center)
            playlistSongsContent(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching
            )
        }
    }

    private func widePlaylistOverview(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: AM.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AM.Spacing.l) {
                playlistArtwork(size: 280)
                    .contextMenu {
                        PlaylistActionsMenuItems(playlist: playlist, songs: songs)
                    } preview: {
                        PlaylistDetailContextPreview(
                            playlist: playlist,
                            songs: songs,
                            coverURLs: playlistCoverURLs
                        )
                    }
                playlistTitleBlock(alignment: .leading)
                if !displayedSongs.isEmpty {
                    actionButtons(songs: displayedSongs, horizontalPadding: 0)
                }
            }
            .frame(width: 320, alignment: .topLeading)

            playlistSongsContent(
                songs: songs,
                displayedSongs: displayedSongs,
                isSearching: isSearching,
                isWideOverview: true,
                rowHorizontalPadding: 0
            )
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .padding(.top, AM.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlaylistDetail.WideOverview")
    }

    private var playlistCoverURLs: [URL] {
        if let url = playlist.explicitCoverURL {
            return [url]
        }
        let songURLs = Playlist.songArtworkURLs(loader.songs ?? playlist.songListDTOs ?? [], limit: 4)
        if !songURLs.isEmpty {
            return songURLs
        }
        return playlist.initialMosaicArtworkURLs
    }

    private func parallaxHero(width: CGFloat) -> some View {
        let baseSize: CGFloat = 240
        return playlistArtwork(size: baseSize)
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            .frame(width: width)
            .frame(height: baseSize)
            .scrollParallaxHero(
                baseSize: baseSize,
                restingOffset: 12,
                fadesWhenCollapsed: true,
                reduceMotion: reduceMotion,
                // Zero, not nil: with `nil` the hero takes the pull for itself,
                // scaling up and sliding *upward* over the search field growing
                // above it — which is why the field appeared behind the artwork.
                // Apple Music gives that space to the search bar instead.
                pullDownOverride: 0
            )
            .padding(.top, 12)
    }

    private func playlistArtwork(size: CGFloat) -> some View {
        PlaylistArtworkContent(playlist: playlist, coverURLs: playlistCoverURLs, cornerRadius: 14)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func playlistTitleBlock(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 4) {
            Text(playlist.name)
                .font(.title2.bold())
                .multilineTextAlignment(alignment)
            if let songCountText {
                Text(songCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 0 : AM.Spacing.screenMargin)
    }

    private var songCountText: String? {
        guard loader.hasAuthoritativeSongs else { return nil }
        let songs = loader.songs ?? playlist.songListDTOs ?? []
        return SongCountText.songs(songs.count)
    }

    @ViewBuilder
    private func playlistSongsContent(
        songs: [Song],
        displayedSongs: [Song],
        isSearching: Bool,
        isWideOverview: Bool = false,
        showsActionButtons: Bool = true,
        rowHorizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        if !displayedSongs.isEmpty {
            VStack(spacing: 0) {
                if showsActionButtons, !isWideOverview {
                    actionButtons(songs: displayedSongs)
                }
                LazyVStack(spacing: 0) {
                    ForEach(displayedSongs.enumerated().map { PositionedPlaylistSong(offset: $0.offset, song: $0.element) }) { item in
                        Button {
                            play(item.song, context: displayedSongs)
                        } label: {
                            PlaylistRow(song: item.song, showsArtwork: true, horizontalPadding: rowHorizontalPadding)
                                .contentShape(Rectangle())
                                .songRowAccessibility(song: item.song) {
                                    play(item.song, context: displayedSongs)
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.985, dim: 0.78, haptic: .selection))
                        .accessibilityHint("Starts playback.")
                        .accessibilityIdentifier("PlaylistDetail.song.\(item.offset).\(item.song.id)")
                        if item.offset < displayedSongs.count - 1 {
                            Divider().padding(.leading, rowHorizontalPadding + 60)
                        }
                    }
                }
                .allowsHitTesting(playbackTapsArmed)
            }
            .environment(\.playlistSongRemoval, songRemovalContext)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else if loader.isLoading, songs.isEmpty {
            PlaylistLoadingRows(horizontalPadding: rowHorizontalPadding)
                .transition(.opacity)
        } else if isSearching, !songs.isEmpty {
            MusicEmptyState(
                title: String(localized: "No Results"),
                message: String(localized: "Try another song title or artist.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
            PlaylistEmptyStateView(
                isFavorites: playlist.isFavorites,
                message: loader.emptyStateMessage
            ) {
                loader.reload(playlistID: playlist.id, fallback: playlist.songListDTOs)
            }
            .padding(.top, 14)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func actionButtons(
        songs: [Song],
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    AppHaptic.selection.play()
                    PlaylistPlayback.playInOrder(first, from: playlist, context: songs)
                }
            } label: {
                LibraryActionButtonLabel(symbol: "play.fill", text: "Play")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Play playlist")
            Button {
                AppHaptic.selection.play()
                PlaylistPlayback.playShuffled(from: playlist, songs: songs)
            } label: {
                LibraryActionButtonLabel(symbol: "shuffle", text: "Shuffle")
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.82))
            .accessibilityLabel("Shuffle playlist")
        }
        .padding(.horizontal, horizontalPadding)
        // Gated here rather than around the caller: the wide overview puts these
        // buttons beside the artwork, outside `playlistSongsContent`.
        .allowsHitTesting(playbackTapsArmed)
    }

    private func play(_ song: Song, context: [Song]) {
        AppHaptic.selection.play()
        PlaylistPlayback.play(song, from: playlist, context: context)
    }

    /// Non-nil only for a playlist the signed-in user owns. Favorites is
    /// excluded: its membership is owned by the star action, which the same
    /// menu already offers.
    private var songRemovalContext: PlaylistSongRemovalContext? {
        // Membership in /api/user/playlists is the whole ownership test. The
        // payload's `editable`/`deletable` flags are NOT usable here: the
        // server returns false for both on playlists the signed-in user created
        // themselves (verified on device), so gating on them hid the action
        // everywhere. `isPersonal` is equally useless — the instance reaching
        // this screen comes from /api/playlists, which leaves it false.
        guard !playlist.isFavorites,
              userPlaylists.playlists.contains(where: { $0.id == playlist.id })
        else { return nil }
        return PlaylistSongRemovalContext(
            playlistID: playlist.id,
            playlistName: playlist.name,
            remove: { song in remove(song) }
        )
    }

    private func remove(_ song: Song) {
        guard let restore = loader.removeSongOptimistically(song) else { return }
        userPlaylists.removeSong(song.id, fromPlaylist: playlist.id) { success in
            guard !success else { return }
            AppHaptic.error.play()
            restore()
            removalErrorSong = song
        }
    }
}

/// Row identity for the playlist song list. The offset keeps IDs unique when
/// a playlist contains the same song twice (duplicate ForEach IDs can hang
/// AttributeGraph). The content fields make the ID change when metadata
/// (artist, duration) arrives after a row was first composed: with purely
/// positional identity, an already-composed row keeps showing the stale
/// "Unknown Artist" from the artist-less list DTOs even after the detail
/// fetch lands, until the whole list is torn down and rebuilt.
private struct PositionedPlaylistSong: Identifiable {
    struct ID: Hashable {
        let offset: Int
        let songID: String
        let displayArtist: String
        let durationText: String
    }

    let offset: Int
    let song: Song

    var id: ID {
        ID(
            offset: offset,
            songID: song.id,
            displayArtist: song.displayArtist,
            durationText: song.durationText
        )
    }
}

private struct PlaylistLoadingRows: View {
    var horizontalPadding: CGFloat = AM.Spacing.screenMargin

    var body: some View {
        CenteredLoadingView(label: "Loading playlist songs")
    }
}

private struct PlaylistEmptyStateView: View {
    let isFavorites: Bool
    let message: String
    let onRefresh: () -> Void
    private var title: String {
        isFavorites ? "No Favorites Yet" : "No Songs"
    }

    private var resolvedMessage: String {
        guard !message.hasPrefix("The playlist") else { return message }
        if isFavorites {
            return "Favorite songs to build this playlist automatically."
        }
        return message
    }

    var body: some View {
        VStack(spacing: 16) {
            MusicEmptyState(title: title, message: resolvedMessage)
            MusicEmptyActionButton(title: "Refresh") {
                onRefresh()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct PlaylistDetailContextPreview: View {
    let playlist: Playlist
    let songs: [Song]
    let coverURLs: [URL]

    var body: some View {
        ContextPreviewCard {
            PlaylistArtworkContent(playlist: playlist, coverURLs: coverURLs, cornerRadius: 10)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.isFavorites ? "Favorites" : "Playlist")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
                Text(playlist.name)
                    .font(AM.Font.tileTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(SongCountText.songs(songs.isEmpty ? playlist.songCount : songs.count))
                    .font(AM.Font.tileCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PlaylistMoreMenu: View {
    let playlist: Playlist
    let songs: [Song]
    let onRefresh: () -> Void
    /// Nil on a playlist the signed-in user cannot edit, which hides the item.
    var onEdit: (() -> Void)?
    var body: some View {
        Menu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Playlist", systemImage: "pencil")
                }
                Divider()
            }
            PlaylistActionsMenuItems(playlist: playlist, songs: songs)
            Divider()
            Button {
                onRefresh()
            } label: {
                Label("Refresh Playlist", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("More Actions", systemImage: "ellipsis")
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .labelStyle(.iconOnly)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.65, haptic: .selection))
        .accessibilityIdentifier("PlaylistDetail.moreActions")
    }
}
