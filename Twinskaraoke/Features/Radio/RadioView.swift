import Combine
import SwiftUI

@MainActor
private final class RadioPlaybackState: ObservableObject {
    static let shared = RadioPlaybackState()

    @Published private(set) var currentSongID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isRadioMode = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let manager = AudioPlayerManager.shared
        manager.$currentSong
            .map(\.?.id)
            .removeDuplicates()
            .sink { [weak self] in self?.currentSongID = $0 }
            .store(in: &cancellables)

        manager.$isPlaying
            .removeDuplicates()
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)

        manager.$isBuffering
            .removeDuplicates()
            .sink { [weak self] in self?.isBuffering = $0 }
            .store(in: &cancellables)

        manager.$isRadioMode
            .removeDuplicates()
            .sink { [weak self] in self?.isRadioMode = $0 }
            .store(in: &cancellables)
    }
}

struct RadioView: View {
    @StateObject private var radio = RadioController.shared
    @ObservedObject private var playback = RadioPlaybackState.shared
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingRadioSchedule = false

    private var metadataPulseAnimation: Animation? {
        reduceMotion ? nil : AppMotion.standard
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if radio.nowPlaying == nil, radio.refreshErrorMessage != nil, !radio.isRefreshing {
                            RadioUnavailableView(
                                message: radio.refreshErrorMessage ?? "Radio metadata is temporarily unavailable.",
                                isRefreshing: radio.isRefreshing
                            ) {
                                Task { await retryRadioRefresh() }
                            }
                            .padding(.top, 36)
                            .transition(unavailableTransition)
                        } else if radio.nowPlaying == nil {
                            RadioSkeletonView()
                                .transition(.opacity)
                        } else {
                            radioOverview(availableWidth: proxy.size.width)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, AM.Spacing.l)
                    .padding(.bottom, AM.Spacing.l)
                }
                .tabBarScrollInset()
                .smoothScrolling(bounceBehavior: .always)
                .musicScreenBackground()
            }
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(
                        systemImage: "list.bullet",
                        accessibilityLabel: "Live Schedule"
                    ) {
                        showLiveSchedule()
                    }
                    .accessibilityHint("Shows live now, up next, and recently played songs.")
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton()
                }
            }
            .refreshable {
                await retryRadioRefresh()
            }
            .onAppear { radio.start() }
            .onDisappear {
                // Polling must keep running while the stream is playing so
                // now-playing metadata stays fresh; stop() only invalidates
                // the metadata poll timer and never touches playback.
                if !playback.isRadioMode {
                    radio.stop()
                }
            }
            .sheet(isPresented: $showingRadioSchedule) {
                RadioQueueView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func retryRadioRefresh() async {
        AppHaptic.selection.play()
        await radio.refresh()
        if radio.refreshErrorMessage != nil {
            AppHaptic.error.play()
        }
    }

    private func playOrPauseLiveStation() {
        if playback.isRadioMode, playback.currentSongID != nil {
            AudioPlayerManager.shared.togglePlayPause()
        } else {
            radio.playLiveStream()
        }
    }

    private func showLiveSchedule() {
        AppHaptic.selection.play()
        #if canImport(UIKit)
            PopupOpenIntentGate.shared.suppressNextOpen()
        #endif
        showingRadioSchedule = true
    }

    private var unavailableTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    private var refreshBannerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }


    @ViewBuilder
    private func radioOverview(availableWidth: CGFloat) -> some View {
        if AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) {
            wideRadioOverview
        } else {
            compactRadioOverview
        }
    }

    private var compactRadioOverview: some View {
        VStack(spacing: AM.Spacing.shelfSpacing) {
            refreshBanner(horizontalPadding: AM.Spacing.screenMargin)
            stationCard(horizontalPadding: 0)
                .padding(.horizontal, AM.Spacing.screenMargin)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity, alignment: .center)
            if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
                historySection(history: history)
            }
        }
    }

    private var wideRadioOverview: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
            refreshBanner(horizontalPadding: 0)

            HStack(alignment: .top, spacing: AM.Spacing.xxl) {
                stationCard(horizontalPadding: 0)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: AM.Spacing.xxl) {
                    if let history = radio.nowPlaying?.songHistory, !history.isEmpty {
                        historySection(history: history, horizontalPadding: 0)
                    }
                }
                .frame(
                    minWidth: AM.Layout.wideInspectorWidth,
                    idealWidth: AM.Layout.wideInspectorWidth,
                    maxWidth: 420,
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: AM.Layout.wideContentMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, AM.Spacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Radio.WideOverview")
    }

    @ViewBuilder
    private func refreshBanner(horizontalPadding: CGFloat) -> some View {
        if let message = radio.refreshErrorMessage, !radio.isRefreshing {
            RadioRefreshBanner(message: message) {
                Task { await retryRadioRefresh() }
            }
            .padding(.horizontal, horizontalPadding)
            .transition(refreshBannerTransition)
        }
    }

    @ViewBuilder
    private var radioActions: some View {
        Button {
            AppHaptic.medium.play()
            radio.playLiveStream()
        } label: {
            Label("Play Live Station", systemImage: "dot.radiowaves.left.and.right")
        }

        Button {
            showLiveSchedule()
        } label: {
            Label("Show Live Schedule", systemImage: "list.bullet")
        }

        Button {
            Task { await retryRadioRefresh() }
        } label: {
            Label("Refresh Metadata", systemImage: "arrow.clockwise")
        }
    }

    @ViewBuilder
    private func stationCard(horizontalPadding: CGFloat = AM.Spacing.screenMargin) -> some View {
        let np = radio.nowPlaying
        let song = np?.nowPlaying?.song
        let isLivePlaying = playback.isRadioMode && playback.isPlaying
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Featured Episode")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityIdentifier("Radio.FeaturedEpisode.Label")
                Text(song?.displayTitle ?? np?.station.name ?? "Twinskaraoke Radio")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityIdentifier("Radio.FeaturedEpisode.Title")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Featured Episode")
            .accessibilityValue(song?.displayTitle ?? np?.station.name ?? "Twinskaraoke Radio")
            .animation(metadataPulseAnimation, value: song?.displayTitle)

            radioHero(
                song: song,
                station: np?.station,
                isLivePlaying: isLivePlaying
            )

            RadioLiveStatusStrip(
                isPlaying: isLivePlaying,
                listenerCount: np?.listeners?.unique,
                lastUpdated: radio.lastUpdated
            )

            if let next = np?.playingNext?.song {
                Button {
                    showLiveSchedule()
                } label: {
                    HStack(spacing: 12) {
                        if let art = next.art, let url = URL(string: art) {
                            RemoteArtworkImage(
                                url: ArtworkURLBuilder.variantURL(from: url, variant: .row) ?? url,
                                cornerRadius: 6,
                                fixedDisplaySize: CGSize(width: 48, height: 48)
                            )
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 48, height: 48)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Up Next")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(next.title ?? next.text ?? "")
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            Text(next.artist ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color.appControlInactiveFill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Up Next")
                .accessibilityValue("\(next.displayTitle), \(next.displayArtist)")
                .accessibilityHint("Shows the live radio schedule.")
                .contextMenu {
                    radioActions
                } preview: {
                    RadioSongContextPreview(song: next)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .contextMenu {
            radioActions
        } preview: {
            RadioStationContextPreview(
                title: song?.displayTitle ?? np?.station.name ?? "Live Radio",
                subtitle: song?.displayArtist ?? np?.station.description ?? "Twinskaraoke Radio",
                artworkURL: song?.artworkURL
            )
        }
    }

    private func radioHero(
        song: RadioNowPlaying.SongInfo?,
        station: RadioNowPlaying.Station?,
        isLivePlaying: Bool
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let art = song?.art, let url = URL(string: art) {
                    RemoteArtworkImage(
                        url: ArtworkURLBuilder.variantURL(from: url, variant: .card) ?? url,
                        cornerRadius: AM.Radius.hero,
                        contentMode: .fill,
                        lowResURL: ArtworkURLBuilder.variantURL(from: url, variant: .thumbnail)
                    )
                } else {
                    artPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.52)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                RadioLiveBadge(isActive: isLivePlaying)
                Text(song?.displayArtist ?? station?.description ?? "Live radio")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(16)

            radioPlayButton(
                isLivePlaying: isLivePlaying,
                accessibilityValue: song?.displayTitle ?? station?.name ?? "Twinskaraoke Radio"
            )
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.hero, style: .continuous))
        .compositingGroup()
        .shadow(color: Color.appHeroShadowIdle, radius: 10, y: 5)
    }

    private func radioPlayButton(isLivePlaying: Bool, accessibilityValue: String) -> some View {
        Button {
            AppHaptic.medium.play()
            playOrPauseLiveStation()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 48, height: 48)
                if playback.isBuffering, playback.isRadioMode, !playback.isPlaying {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
                        .font(.title3.bold())
                        .foregroundStyle(Color.black)
                        .offset(x: isLivePlaying ? 0 : 2)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9, dim: 0.85))
        .accessibilityLabel(isLivePlaying ? "Pause live station" : "Play live station")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Controls the live radio stream.")
    }

    private var artPlaceholder: some View {
        MusicArtworkPlaceholder(cornerRadius: 0)
    }

    private func historySection(
        history: [RadioNowPlaying.HistoryItem],
        horizontalPadding: CGFloat = AM.Spacing.screenMargin
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RadioSectionHeader("New & Recent")
                .padding(.horizontal, horizontalPadding)
            LazyVStack(spacing: 0) {
                ForEach(Array(history.prefix(10).enumerated()), id: \.offset) { _, item in
                    Button {
                        showLiveSchedule()
                    } label: {
                        RadioHistoryRow(song: item.song)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.78))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recently played")
                    .accessibilityValue("\(item.song.displayTitle), \(item.song.displayArtist)")
                    .accessibilityHint("Shows the live radio schedule.")
                    .contextMenu {
                        radioActions
                    } preview: {
                        RadioSongContextPreview(song: item.song)
                    }
                    Divider().padding(.leading, 76)
                }
            }
        }
        .accessibilityIdentifier("Radio.HistorySection")
    }
}

private struct RadioSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
            Text(title)
                .font(AM.Font.sectionHeader)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 2)
    }
}

private struct RadioLiveBadge: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(.white.opacity(isActive ? 0.26 : 0.12))
                    .frame(width: isActive ? 11 : 8, height: isActive ? 11 : 8)
                    .accessibilityHidden(true)
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 12, height: 12)

            Text("LIVE")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.appAccent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Live and playing" : "Live")
    }
}

private struct RadioLiveStatusStrip: View {
    let isPlaying: Bool
    let listenerCount: Int?
    let lastUpdated: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statusPills
            }
            VStack(spacing: 6) {
                statusPills
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusPills: some View {
        RadioStatusPill(
            systemImage: isPlaying ? "speaker.wave.2.fill" : "dot.radiowaves.left.and.right",
            text: isPlaying ? "On Air" : "Live Ready",
            tint: .appAccent
        )
        if let listenerCount {
            RadioStatusPill(
                systemImage: "person.2.fill",
                text: listenerCount == 1 ? "1 listening" : "\(listenerCount) listening",
                tint: .secondary
            )
        }
        if let lastUpdated {
            RadioStatusPill(
                systemImage: "clock",
                text: "Updated \(lastUpdated.formatted(.relative(presentation: .named)))",
                tint: .secondary
            )
        }
    }
}

private struct RadioStatusPill: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(Color.appControlInactiveFill)
            )
    }
}

private struct RadioRefreshBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                onRetry()
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.appSecondaryBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.appDivider, lineWidth: 0.6)
                    }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.7))
            .accessibilityLabel("Retry")
            .accessibilityHint("Refreshes radio metadata.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.appControlInactiveFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct RadioUnavailableView: View {
    let message: String
    let isRefreshing: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            MusicEmptyState(
                title: "Radio Unavailable",
                message: message
            )
            MusicEmptyActionButton(title: isRefreshing ? "Refreshing" : "Try Again") {
                onRetry()
            }
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "Refreshing radio metadata" : "Try again")
            .accessibilityHint("Refreshes the live radio station metadata.")
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct RadioStationContextPreview: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?

    var body: some View {
        ContextPreviewCard {
            Group {
                if let artworkURL {
                    RemoteArtworkImage(
                        url: ArtworkURLBuilder.variantURL(from: artworkURL, variant: .card) ?? artworkURL,
                        cornerRadius: 10,
                        lowResURL: ArtworkURLBuilder.variantURL(from: artworkURL, variant: .thumbnail)
                    )
                } else {
                    MusicArtworkPlaceholder(cornerRadius: 10)
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Live Station")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct RadioSongContextPreview: View {
    let song: RadioNowPlaying.SongInfo

    var body: some View {
        RadioStationContextPreview(
            title: song.displayTitle,
            subtitle: song.displayArtist,
            artworkURL: song.artworkURL
        )
    }
}

private struct RadioHistoryRow: View {
    let song: RadioNowPlaying.SongInfo
    var body: some View {
        HStack(spacing: 12) {
            if let art = song.art, let url = URL(string: art) {
                RemoteArtworkImage(
                    url: ArtworkURLBuilder.variantURL(from: url, variant: .row) ?? url,
                    cornerRadius: 6,
                    fixedDisplaySize: CGSize(width: 48, height: 48)
                )
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? song.text ?? "")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct RadioSkeletonView: View {
    var body: some View {
        CenteredLoadingView(label: "Loading Radio")
    }
}
