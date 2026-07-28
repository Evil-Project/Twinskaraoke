#if canImport(CarPlay) && canImport(UIKit)
import CarPlay
import Combine
import SDWebImage
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
    CPNowPlayingTemplateObserver, CPInterfaceControllerDelegate
{
    private weak var interfaceController: CPInterfaceController?
    private let player = AudioPlayerManager.shared
    private let radio = RadioController.shared
    private let artworkLoader = CarPlayArtworkLoader()
    private let maximumBrowseRows = 24

    private var playlistsTemplate: CPListTemplate?
    private var latestTemplate: CPListTemplate?
    private var radioTemplate: CPListTemplate?
    private var upNextTemplate: CPListTemplate?
    private var randomTemplate: CPListTemplate?

    private var serverPlaylists: [Playlist] = []
    private var favoritesSongCount = 0
    private var latestSongs: [Song] = []
    private var randomSongs: [Song] = []

    private var contentTasks: [Task<Void, Never>] = []
    private var playlistLoadTasks: [String: Task<Void, Never>] = [:]
    private var openPlaylistTemplates: [String: CPListTemplate] = [:]
    private var openPlaylistSongs: [String: [Song]] = [:]
    private var openPlaylists: [String: Playlist] = [:]
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        log("CarPlay scene connected")
        self.interfaceController = interfaceController
        interfaceController.delegate = self
        configureNowPlayingTemplate()
        observeContentChanges()

        let playlists = makeRootListTemplate(title: "Playlists", tabTitle: "Library", systemImage: "music.note.list")
        let latest = makeRootListTemplate(title: "New", tabTitle: "New", systemImage: "sparkles")
        let radio = makeRootListTemplate(title: "Radio", tabTitle: "Radio", systemImage: "dot.radiowaves.left.and.right")
        let upNext = makeRootListTemplate(title: "Up Next", tabTitle: "Up Next", systemImage: "list.bullet")
        let random = makeRootListTemplate(title: "Random", tabTitle: "Random", systemImage: "shuffle")

        playlistsTemplate = playlists
        latestTemplate = latest
        radioTemplate = radio
        upNextTemplate = upNext
        randomTemplate = random

        let rootTemplates = [playlists, latest, radio, upNext, random]
        let maxTabs = max(1, CPTabBarTemplate.maximumTabCount)
        let tabBarTemplate = CPTabBarTemplate(templates: Array(rootTemplates.prefix(maxTabs)))
        interfaceController.setRootTemplate(tabBarTemplate, animated: false) { [weak self] success, error in
            if let error {
                self?.log("Unable to set CarPlay root template: \(error.localizedDescription)")
            } else {
                self?.log("CarPlay root template set: \(success)")
            }
        }

        loadCarPlayContent()
        UserPlaylistsManager.shared.loadIfNeeded()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        CPNowPlayingTemplate.shared.remove(self)
        interfaceController.delegate = nil
        contentTasks.forEach { $0.cancel() }
        playlistLoadTasks.values.forEach { $0.cancel() }
        artworkLoader.cancelAll()
        contentTasks.removeAll()
        playlistLoadTasks.removeAll()
        openPlaylistTemplates.removeAll()
        openPlaylistSongs.removeAll()
        openPlaylists.removeAll()
        cancellables.removeAll()
        self.interfaceController = nil
        if !player.isRadioMode {
            radio.stop()
        }
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        showQueueTemplate()
    }

    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        guard let interfaceController,
              !interfaceController.templates.contains(where: { $0 === aTemplate }),
              let playlistID = openPlaylistTemplates.first(where: { $0.value === aTemplate })?.key,
              openPlaylistTemplates[playlistID] === aTemplate
        else { return }

        playlistLoadTasks.removeValue(forKey: playlistID)?.cancel()
        openPlaylistTemplates.removeValue(forKey: playlistID)
        openPlaylistSongs.removeValue(forKey: playlistID)
        openPlaylists.removeValue(forKey: playlistID)
    }

    private func configureNowPlayingTemplate() {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared
        nowPlayingTemplate.add(self)
        nowPlayingTemplate.isUpNextButtonEnabled = true
        nowPlayingTemplate.upNextTitle = "Up Next"
        nowPlayingTemplate.isAlbumArtistButtonEnabled = false
    }

    private func observeContentChanges() {
        cancellables.removeAll()

        let signals: [AnyPublisher<Void, Never>] = [
            player.$currentSong.dropFirst().map { _ in }.eraseToAnyPublisher(),
            player.$isPlaying.dropFirst().map { _ in }.eraseToAnyPublisher(),
            player.$queue.dropFirst().map { _ in }.eraseToAnyPublisher(),
            radio.$nowPlaying.dropFirst().map { _ in }.eraseToAnyPublisher(),
            radio.$isRefreshing.dropFirst().map { _ in }.eraseToAnyPublisher(),
            radio.$refreshErrorMessage.dropFirst().map { _ in }.eraseToAnyPublisher(),
            radio.$lastUpdated.dropFirst().map { _ in }.eraseToAnyPublisher(),
            SavedPlaylistsStore.shared.$playlists.dropFirst().map { _ in }.eraseToAnyPublisher(),
            UserPlaylistsManager.shared.$playlists.dropFirst().map { _ in }.eraseToAnyPublisher(),
            FavoritesManager.shared.$favoriteIDs.dropFirst().map { _ in }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(signals)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshVisibleTemplates()
            }
            .store(in: &cancellables)
    }

    private func loadCarPlayContent() {
        contentTasks.forEach { $0.cancel() }
        contentTasks.removeAll()

        playlistsTemplate?.updateSections([statusSection("Loading Playlists")])
        latestTemplate?.updateSections([statusSection("Loading New Songs")])
        radioTemplate?.updateSections(radioSections())
        upNextTemplate?.updateSections(upNextSections())
        randomTemplate?.updateSections([statusSection("Loading Random Songs")])

        radio.start()
        loadPlaylists()
        loadLatestSongs()
        loadRandomSongs()
    }

    private func loadPlaylists() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                async let serverResult = KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: maximumBrowseRows,
                    isSetlist: false,
                    sortDescending: false
                )
                async let favoritesResult = KaraokeAPIClient.favoriteSongs()

                let loadedPlaylists = try await serverResult
                let loadedFavorites = (try? await favoritesResult) ?? []
                guard !Task.isCancelled else { return }

                serverPlaylists = loadedPlaylists
                favoritesSongCount = max(FavoritesManager.shared.favoriteIDs.count, loadedFavorites.count)
                rebuildPlaylistsTemplate()
            } catch {
                guard !Task.isCancelled else { return }
                serverPlaylists = []
                favoritesSongCount = FavoritesManager.shared.favoriteIDs.count
                playlistsTemplate?.updateSections([
                    controlsSection(reloadAction: { [weak self] in self?.loadPlaylists() }),
                    statusSection("Unable to Load Playlists", detail: "Check the connection and try again.", enabled: false),
                ])
            }
        }
        contentTasks.append(task)
    }

    private func loadLatestSongs() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.latestReleases(take: maximumBrowseRows)
                guard !Task.isCancelled else { return }
                latestSongs = songs
                rebuildLatestTemplate()
            } catch {
                guard !Task.isCancelled else { return }
                latestSongs = []
                latestTemplate?.updateSections([
                    controlsSection(reloadAction: { [weak self] in self?.loadLatestSongs() }),
                    statusSection("Unable to Load New Songs", detail: "Check the connection and try again.", enabled: false),
                ])
            }
        }
        contentTasks.append(task)
    }

    private func loadRandomSongs() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await KaraokeAPIClient.randomSongs()
                guard !Task.isCancelled else { return }
                randomSongs = Array(songs.prefix(maximumBrowseRows))
                rebuildRandomTemplate()
            } catch {
                guard !Task.isCancelled else { return }
                randomSongs = []
                randomTemplate?.updateSections([
                    controlsSection(reloadAction: { [weak self] in self?.loadRandomSongs() }),
                    statusSection("Unable to Load Random Songs", detail: "Check the connection and try again.", enabled: false),
                ])
            }
        }
        contentTasks.append(task)
    }

    private func refreshVisibleTemplates() {
        favoritesSongCount = max(favoritesSongCount, FavoritesManager.shared.favoriteIDs.count)
        rebuildPlaylistsTemplate()
        rebuildLatestTemplate()
        rebuildRadioTemplate()
        rebuildUpNextTemplate()
        rebuildRandomTemplate()

        for (playlistID, template) in openPlaylistTemplates {
            guard let playlist = openPlaylists[playlistID], let songs = openPlaylistSongs[playlistID] else { continue }
            updatePlaylistTemplate(template, playlist: playlist, songs: songs)
        }
    }

    private func rebuildPlaylistsTemplate() {
        guard let playlistsTemplate else { return }
        configureNavigationButtons(for: playlistsTemplate, reloadAction: { [weak self] in self?.loadPlaylists() })

        let playlists = currentPlaylists()
        guard !playlists.isEmpty else {
            playlistsTemplate.updateSections([
                controlsSection(reloadAction: { [weak self] in self?.loadPlaylists() }),
                statusSection("No Playlists", detail: "Saved and server playlists will appear here.", enabled: false),
            ])
            return
        }

        let items = playlists.prefix(maximumBrowseRows).map { playlist in
            playlistListItem(playlist)
        }
        playlistsTemplate.updateSections([
            controlsSection(reloadAction: { [weak self] in self?.loadPlaylists() }),
            CPListSection(items: Array(items), header: "Browse", sectionIndexTitle: nil),
        ])
    }

    private func rebuildLatestTemplate() {
        guard let latestTemplate else { return }
        configureNavigationButtons(for: latestTemplate, reloadAction: { [weak self] in self?.loadLatestSongs() })

        guard !latestSongs.isEmpty else {
            latestTemplate.updateSections([
                controlsSection(reloadAction: { [weak self] in self?.loadLatestSongs() }),
                statusSection("No New Songs", detail: "Try reloading this list.", enabled: false),
            ])
            return
        }

        latestTemplate.updateSections([
            songActionSection(title: "New Songs", songs: latestSongs),
            CPListSection(items: songItems(latestSongs, context: latestSongs), header: "Songs", sectionIndexTitle: nil),
        ])
    }

    private func rebuildRadioTemplate() {
        guard let radioTemplate else { return }
        configureNavigationButtons(for: radioTemplate, reloadAction: { [weak self] in
            Task { @MainActor in
                await self?.refreshRadioMetadata()
            }
        })
        radioTemplate.updateSections(radioSections())
    }

    private func rebuildRandomTemplate() {
        guard let randomTemplate else { return }
        configureNavigationButtons(for: randomTemplate, reloadAction: { [weak self] in self?.loadRandomSongs() })

        guard !randomSongs.isEmpty else {
            randomTemplate.updateSections([
                controlsSection(reloadAction: { [weak self] in self?.loadRandomSongs() }),
                statusSection("No Random Songs", detail: "Try reloading this list.", enabled: false),
            ])
            return
        }

        randomTemplate.updateSections([
            songActionSection(title: "Random Songs", songs: randomSongs, includeRefresh: true),
            CPListSection(items: songItems(randomSongs, context: randomSongs), header: "Songs", sectionIndexTitle: nil),
        ])
    }

    private func radioSections() -> [CPListSection] {
        var sections = [radioControlsSection()]

        guard let nowPlaying = radio.nowPlaying else {
            if radio.isRefreshing {
                sections.append(statusSection("Loading Radio", detail: "Fetching live station metadata.", enabled: false))
            } else if let message = radio.refreshErrorMessage {
                sections.append(statusSection("Radio Unavailable", detail: message, enabled: false))
            } else {
                sections.append(statusSection("Radio Metadata", detail: "Refresh to load the live station.", enabled: false))
            }
            return sections
        }

        if let liveSong = nowPlaying.nowPlaying?.song {
            sections.append(
                CPListSection(
                    items: [radioSongItem(liveSong, isCurrent: true)],
                    header: "Live Now",
                    sectionIndexTitle: nil
                )
            )
        }

        if let nextSong = nowPlaying.playingNext?.song {
            sections.append(
                CPListSection(
                    items: [radioSongItem(nextSong, isCurrent: false)],
                    header: "Up Next",
                    sectionIndexTitle: nil
                )
            )
        }

        let historyItems = Array((nowPlaying.songHistory ?? []).prefix(maximumBrowseRows)).map(\.song)
        if !historyItems.isEmpty {
            sections.append(
                CPListSection(
                    items: historyItems.map { radioSongItem($0, isCurrent: false) },
                    header: "Recently Played",
                    sectionIndexTitle: nil
                )
            )
        }

        if sections.count == 1 {
            sections.append(
                statusSection("Radio Schedule Unavailable", detail: "Refresh to load live station metadata.", enabled: false)
            )
        }

        return sections
    }

    private func rebuildUpNextTemplate() {
        guard let upNextTemplate else { return }
        configureNavigationButtons(for: upNextTemplate, reloadAction: nil)
        upNextTemplate.updateSections(upNextSections())
    }

    private func currentPlaylists() -> [Playlist] {
        let favorites = Playlist(
            id: Playlist.favoritesID,
            name: "Favourite Songs",
            songCount: favoritesSongCount,
            mosaicMedia: nil,
            songListDTOs: nil
        )
        var seenIDs = Set<String>()
        var playlists: [Playlist] = []

        func append(_ playlist: Playlist) {
            guard seenIDs.insert(playlist.id).inserted else { return }
            playlists.append(playlist)
        }

        UserPlaylistsManager.shared.playlists.map { $0.asPlaylist() }.forEach(append)
        append(favorites)
        serverPlaylists.forEach(append)
        SavedPlaylistsStore.shared.playlists.forEach(append)
        return playlists
    }

    private func makeRootListTemplate(title: String, tabTitle: String, systemImage: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [statusSection("Loading")])
        template.tabTitle = tabTitle
        template.tabImage = UIImage(systemName: systemImage)
        template.emptyViewTitleVariants = ["Nothing Here"]
        template.emptyViewSubtitleVariants = ["Reload to try again."]
        configureNavigationButtons(for: template, reloadAction: { [weak self] in self?.loadCarPlayContent() })
        return template
    }

    private func playlistListItem(_ playlist: Playlist) -> CPListItem {
        let item = CPListItem(text: playlist.name, detailText: playlistDetailText(playlist))
        item.handler = { [weak self] _, completion in
            self?.showPlaylist(playlist, completion: completion)
        }
        return item
    }

    private func showPlaylist(_ playlist: Playlist, completion: @escaping () -> Void) {
        let template = CPListTemplate(title: playlist.name, sections: [statusSection("Loading Songs")])
        configureNavigationButtons(for: template, reloadAction: { [weak self, weak template] in
            guard let self, let template else { return }
            self.loadPlaylistSongs(for: playlist, into: template)
        })

        guard let interfaceController else {
            completion()
            return
        }

        openPlaylists[playlist.id] = playlist
        openPlaylistTemplates[playlist.id] = template

        interfaceController.pushTemplate(template, animated: true) { [weak self] _, _ in
            completion()
            self?.loadPlaylistSongs(for: playlist, into: template)
        }
    }

    private func loadPlaylistSongs(for playlist: Playlist, into template: CPListTemplate) {
        playlistLoadTasks[playlist.id]?.cancel()
        template.updateSections([statusSection("Loading Songs")])

        if let fallbackSongs = playlist.songListDTOs, !fallbackSongs.isEmpty {
            openPlaylistSongs[playlist.id] = fallbackSongs
            updatePlaylistTemplate(template, playlist: playlist, songs: fallbackSongs)
        }

        let task = Task { [weak self, weak template] in
            guard let self, let template else { return }
            do {
                let songs = try await KaraokeAPIClient.playlistSongs(id: playlist.id)
                guard !Task.isCancelled else { return }
                openPlaylistSongs[playlist.id] = songs
                updatePlaylistTemplate(template, playlist: playlist, songs: songs)
            } catch {
                guard !Task.isCancelled else { return }
                if openPlaylistSongs[playlist.id]?.isEmpty ?? true {
                    template.updateSections([
                        controlsSection(reloadAction: { [weak self, weak template] in
                            guard let self, let template else { return }
                            self.loadPlaylistSongs(for: playlist, into: template)
                        }),
                        statusSection("Unable to Load Songs", detail: "Check the connection and try again.", enabled: false),
                    ])
                }
            }
        }
        playlistLoadTasks[playlist.id] = task
    }

    private func updatePlaylistTemplate(_ template: CPListTemplate, playlist: Playlist, songs: [Song]) {
        configureNavigationButtons(for: template, reloadAction: { [weak self, weak template] in
            guard let self, let template else { return }
            self.loadPlaylistSongs(for: playlist, into: template)
        })

        guard !songs.isEmpty else {
            template.updateSections([
                controlsSection(reloadAction: { [weak self, weak template] in
                    guard let self, let template else { return }
                    self.loadPlaylistSongs(for: playlist, into: template)
                }),
                statusSection("No Songs", detail: "This playlist is empty.", enabled: false),
            ])
            return
        }

        template.updateSections([
            songActionSection(title: playlist.name, songs: songs),
            CPListSection(items: songItems(songs, context: songs), header: "Songs", sectionIndexTitle: nil),
        ])
    }

    private func showQueueTemplate() {
        guard let interfaceController else { return }
        let template = CPListTemplate(title: "Up Next", sections: upNextSections())
        configureNavigationButtons(for: template, reloadAction: nil)
        interfaceController.pushTemplate(template, animated: true) { [weak self] _, error in
            if let error {
                self?.log("Unable to show CarPlay queue: \(error.localizedDescription)")
            }
        }
    }

    private func upNextSections() -> [CPListSection] {
        let snapshot = upNextSnapshot()
        var sections = [controlsSection(reloadAction: nil)]

        guard !snapshot.songs.isEmpty else {
            sections.append(
                statusSection(
                    "No Upcoming Songs",
                    detail: "Play a playlist or song list to fill the queue.",
                    enabled: false
                )
            )
            return sections
        }

        sections.append(
            CPListSection(
                items: songItems(snapshot.songs, context: snapshot.context),
                header: "Coming Up",
                sectionIndexTitle: nil
            )
        )
        return sections
    }

    private func upNextSnapshot() -> (songs: [Song], context: [Song]) {
        let context = player.queue
        guard !context.isEmpty else { return ([], []) }
        guard let currentID = player.currentSong?.id,
              let currentIndex = context.firstIndex(where: { $0.id == currentID })
        else {
            return (context, context)
        }
        let nextIndex = currentIndex + 1
        guard nextIndex < context.count else { return ([], context) }
        return (Array(context[nextIndex...]), context)
    }

    private func showNowPlaying() {
        guard let interfaceController, player.currentSong != nil else { return }
        let nowPlayingTemplate = CPNowPlayingTemplate.shared

        if let topTemplate = interfaceController.topTemplate, topTemplate === nowPlayingTemplate { return }
        if interfaceController.templates.contains(where: { $0 === nowPlayingTemplate }) {
            interfaceController.pop(to: nowPlayingTemplate, animated: true) { _, _ in }
            return
        }

        interfaceController.pushTemplate(nowPlayingTemplate, animated: true) { [weak self] _, error in
            if let error {
                self?.log("Unable to show CarPlay Now Playing: \(error.localizedDescription)")
            }
        }
    }

    private func configureNavigationButtons(for template: CPListTemplate, reloadAction: (() -> Void)?) {
        var buttons: [CPBarButton] = []

        let nowButton = CPBarButton(title: "Now") { [weak self] _ in
            self?.showNowPlaying()
        }
        nowButton.isEnabled = player.currentSong != nil
        buttons.append(nowButton)

        if let reloadAction {
            buttons.append(CPBarButton(title: "Reload") { _ in reloadAction() })
        }

        template.trailingNavigationBarButtons = Array(buttons.prefix(2))
    }

    private func controlsSection(reloadAction: (() -> Void)?) -> CPListSection {
        var items: [CPListItem] = []

        let nowPlaying = CPListItem(
            text: player.currentSong?.title ?? "Now Playing",
            detailText: player.currentSong.map { songDetailText($0) } ?? "No song is currently playing."
        )
        nowPlaying.isEnabled = player.currentSong != nil
        nowPlaying.isPlaying = player.currentSong != nil
        nowPlaying.handler = { [weak self] _, completion in
            self?.showNowPlaying()
            completion()
        }
        items.append(nowPlaying)

        if let reloadAction {
            let reload = CPListItem(text: "Reload", detailText: "Refresh this CarPlay list")
            reload.handler = { _, completion in
                reloadAction()
                completion()
            }
            items.append(reload)
        }

        return CPListSection(items: items, header: nil, sectionIndexTitle: nil)
    }

    private func radioControlsSection() -> CPListSection {
        var items: [CPListItem] = []
        let stationName = radio.nowPlaying?.station.name ?? "Twinskaraoke Radio"

        let playPause = CPListItem(
            text: radioPlayPauseTitle,
            detailText: radioControlDetail(stationName: stationName),
            image: fallbackRadioImage(),
            accessoryImage: nil,
            accessoryType: .none
        )
        playPause.isPlaying = player.isRadioMode && player.isPlaying
        playPause.handler = { [weak self] _, completion in
            self?.playOrPauseLiveRadio()
            completion()
        }
        items.append(playPause)

        let refresh = CPListItem(text: radio.isRefreshing ? "Refreshing Radio" : "Refresh Radio", detailText: "Update live, next, and history")
        refresh.isEnabled = !radio.isRefreshing
        refresh.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.refreshRadioMetadata()
                completion()
            }
        }
        items.append(refresh)

        return CPListSection(items: items, header: stationName, sectionIndexTitle: nil)
    }

    private var radioPlayPauseTitle: String {
        if player.isRadioMode {
            return player.isPlaying ? "Pause Live Radio" : "Resume Live Radio"
        }
        return "Play Live Radio"
    }

    private func radioControlDetail(stationName: String) -> String? {
        if let listeners = radio.nowPlaying?.listeners {
            return "\(stationName) - \(listeners.unique) listening"
        }
        return stationName
    }

    private func playOrPauseLiveRadio() {
        if player.isRadioMode, player.currentSong != nil {
            player.togglePlayPause()
        } else {
            radio.start()
            radio.playLiveStream()
        }
        rebuildRadioTemplate()
        showNowPlaying()
    }

    private func refreshRadioMetadata() async {
        await radio.refresh()
        rebuildRadioTemplate()
    }

    private func songActionSection(title: String, songs: [Song], includeRefresh: Bool = false) -> CPListSection {
        var items: [CPListItem] = []

        let playAll = CPListItem(text: "Play All", detailText: SongCountText.songs(songs.count))
        playAll.isEnabled = !songs.isEmpty
        playAll.handler = { [weak self] _, completion in
            if let first = songs.first {
                self?.play(first, in: songs)
            }
            completion()
        }
        items.append(playAll)

        let shuffle = CPListItem(text: "Shuffle", detailText: title)
        shuffle.isEnabled = !songs.isEmpty
        shuffle.handler = { [weak self] _, completion in
            self?.playShuffled(songs)
            completion()
        }
        items.append(shuffle)

        if includeRefresh {
            let refresh = CPListItem(text: "Refresh Random", detailText: "Load another set")
            refresh.handler = { [weak self] _, completion in
                self?.loadRandomSongs()
                completion()
            }
            items.append(refresh)
        }

        return CPListSection(items: items, header: nil, sectionIndexTitle: nil)
    }

    private func songItems(_ songs: [Song], context: [Song]) -> [CPListItem] {
        songs.prefix(maximumBrowseRows).map { song in
            songItem(song, context: context)
        }
    }

    private func songItem(_ song: Song, context: [Song]) -> CPListItem {
        let item = CPListItem(
            text: song.title,
            detailText: songDetailText(song),
            image: fallbackSongImage(),
            accessoryImage: nil,
            accessoryType: .none
        )
        item.isPlaying = player.currentSong?.id == song.id
        item.handler = { [weak self] _, completion in
            self?.play(song, in: context)
            completion()
        }
        loadSongArtwork(for: song, into: item)
        return item
    }

    private func radioSongItem(_ song: RadioNowPlaying.SongInfo, isCurrent: Bool) -> CPListItem {
        let item = CPListItem(
            text: song.displayTitle,
            detailText: isCurrent ? radioCurrentSongDetail(song) : song.displayArtist,
            image: fallbackRadioImage(),
            accessoryImage: nil,
            accessoryType: .none
        )
        item.isEnabled = isCurrent
        item.isPlaying = isCurrent && player.isRadioMode && player.isPlaying
        item.handler = { [weak self] _, completion in
            if isCurrent {
                self?.playOrPauseLiveRadio()
            }
            completion()
        }
        loadRadioArtwork(for: song, into: item)
        return item
    }

    private func radioCurrentSongDetail(_ song: RadioNowPlaying.SongInfo) -> String {
        if player.isRadioMode, player.isPlaying {
            return "\(song.displayArtist) - On air now"
        }
        return "\(song.displayArtist) - Live station"
    }

    private func loadSongArtwork(for song: Song, into item: CPListItem) {
        guard let url = player.displayImageURL(for: song, variant: .row) ?? song.thumbnailURL ?? song.imageURL else {
            return
        }

        let targetSize = carPlayListArtworkSize()
        let displayScale = interfaceController?.carTraitCollection.displayScale ?? 2
        artworkLoader.loadImage(from: url, targetSize: targetSize, displayScale: displayScale) { [weak item] image in
            item?.setImage(image)
        }
    }

    private func loadRadioArtwork(for song: RadioNowPlaying.SongInfo, into item: CPListItem) {
        guard let artworkURL = song.artworkURL else { return }
        let url = ArtworkURLBuilder.variantURL(from: artworkURL, variant: .row) ?? artworkURL
        let targetSize = carPlayListArtworkSize()
        let displayScale = interfaceController?.carTraitCollection.displayScale ?? 2
        artworkLoader.loadImage(from: url, targetSize: targetSize, displayScale: displayScale) { [weak item] image in
            item?.setImage(image)
        }
    }

    private func carPlayListArtworkSize() -> CGSize {
        let maximumSize = CPListItem.maximumImageSize
        guard maximumSize.width > 0, maximumSize.height > 0 else {
            return CGSize(width: 56, height: 56)
        }
        return maximumSize
    }

    private func fallbackSongImage() -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        return UIImage(systemName: "music.note", withConfiguration: configuration) ?? UIImage()
    }

    private func fallbackRadioImage() -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        return UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: configuration) ?? fallbackSongImage()
    }

    private func play(_ song: Song, in context: [Song]) {
        player.playInOrder(song: song, context: context.isEmpty ? [song] : context)
        refreshVisibleTemplates()
        showNowPlaying()
    }

    private func playShuffled(_ songs: [Song]) {
        player.playShuffled(from: songs)
        refreshVisibleTemplates()
        showNowPlaying()
    }

    private func statusSection(_ title: String, detail: String? = nil, enabled: Bool = false) -> CPListSection {
        let item = CPListItem(text: title, detailText: detail)
        item.isEnabled = enabled
        return CPListSection(items: [item], header: nil, sectionIndexTitle: nil)
    }

    private func playlistDetailText(_ playlist: Playlist) -> String? {
        var parts = [String]()
        parts.append(SongCountText.songs(playlist.songCount))
        if playlist.isPersonal { parts.append("Personal") }
        if SavedPlaylistsStore.shared.isSaved(playlist) { parts.append("Saved") }
        return parts.joined(separator: " - ")
    }

    private func songDetailText(_ song: Song) -> String? {
        var parts = [String]()
        let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty { parts.append(artist) }
        if !song.durationText.isEmpty { parts.append(song.durationText) }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    private func log(_ message: String) {
        DebugLogger.log(message, category: .ui)
    }
}

@MainActor
private final class CarPlayArtworkLoader {
    private let cache = NSCache<NSURL, UIImage>()
    private var operations: [NSURL: any SDWebImageOperation] = [:]
    private var completions: [NSURL: [@MainActor (UIImage) -> Void]] = [:]

    func loadImage(
        from url: URL,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping @MainActor (UIImage) -> Void
    ) {
        let cacheKey = url as NSURL
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        completions[cacheKey, default: []].append(completion)
        guard operations[cacheKey] == nil else { return }

        operations[cacheKey] = SDWebImageManager.shared.loadImage(
            with: url,
            options: [],
            context: ImageCacheConfig.memoryAndDiskCacheContext,
            progress: nil
        ) { [weak self] image, _, _, _, _, _ in
            guard let image else {
                Task { @MainActor [weak self] in
                    self?.finishLoading(cacheKey, image: nil)
                }
                return
            }

            let maxPixel = max(targetSize.width, targetSize.height) * max(displayScale, 1)
            let processedImage = image.croppedToSquare().downscaled(maxPixel: maxPixel)
            Task { @MainActor [weak self] in
                self?.finishLoading(cacheKey, image: processedImage)
            }
        }
    }

    func cancelAll() {
        operations.values.forEach { $0.cancel() }
        operations.removeAll()
        completions.removeAll()
    }

    private func finishLoading(_ cacheKey: NSURL, image: UIImage?) {
        operations[cacheKey] = nil
        let handlers = completions.removeValue(forKey: cacheKey) ?? []
        guard let image else { return }
        cache.setObject(image, forKey: cacheKey)
        handlers.forEach { $0(image) }
    }
}
#endif
