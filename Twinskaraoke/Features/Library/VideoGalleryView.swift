import SwiftUI

struct VideoGalleryView: View {
    @Namespace private var zoomNamespace
    @State private var viewModel = VideoGalleryViewModel()
    @State private var filter: VideoGalleryFilter = .all
    private let cols = AM.Layout.adaptiveGridColumns(minimum: 164, spacing: 16)

    private var videos: [GalleryVideo] {
        filter.apply(to: viewModel.videos)
    }

    var body: some View {
        ScrollView {
            if viewModel.videos.isEmpty, viewModel.isLoading {
                VideoGallerySkeleton()
                    .padding(.top, AM.Spacing.l)
            } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
                VideoGalleryStateView(
                    title: "Couldn't Load Videos",
                    message: message,
                    buttonTitle: "Try Again"
                ) {
                    viewModel.refresh()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.videos.isEmpty {
                VideoGalleryStateView(
                    title: "No Videos",
                    message: "Recent Twinskaraoke videos will appear here.",
                    buttonTitle: "Refresh"
                ) {
                    viewModel.refresh()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                galleryContent
            }
        }
        .scrollIndicators(.hidden)
        .smoothScrolling()
        .musicScreenBackground()
        .navigationTitle("Video Gallery")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            AppHaptic.selection.play()
            await viewModel.refreshVideos()
        }
        .onAppear { viewModel.fetchInitial() }
    }

    @ViewBuilder
    private var galleryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let featured = videos.first {
                ZoomNavigationLink(id: featured.id, in: zoomNamespace) {
                    VideoPlayerScreen(video: featured)
                } label: {
                    FeaturedVideoCard(video: featured, isWatchalongFilter: filter == .watchalongs)
                }
                .buttonStyle(PressableButtonStyle(haptic: .selection))
                .contextMenu {
                    VideoActionsMenu(video: featured)
                } preview: {
                    VideoContextPreview(video: featured, isFeatured: true)
                }
                .padding(.horizontal, AM.Spacing.screenMargin)
            }

            // Above the filter bar because it is account state, not a slice of
            // the feed — the filter below has nothing to say about it.
            ContinueWatchingSection(zoomNamespace: zoomNamespace)

            VideoGalleryFilterBar(filter: $filter)
                .padding(.horizontal, AM.Spacing.screenMargin)

            if videos.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text(filter.sectionTitle)
                        .scaledSystemFont(size: 22, weight: .bold)
                        .padding(.horizontal, AM.Spacing.screenMargin)
                    LazyVGrid(columns: cols, spacing: 20) {
                        ForEach(videos.dropFirst()) { video in
                            ZoomNavigationLink(id: video.id, in: zoomNamespace) {
                                VideoPlayerScreen(video: video)
                            } label: {
                                VideoGalleryCell(video: video)
                            }
                            .buttonStyle(PressableButtonStyle(haptic: .selection))
                            .contextMenu {
                                VideoActionsMenu(video: video)
                            } preview: {
                                VideoContextPreview(video: video)
                            }
                            // `loadMoreIfNeeded` measures against the unfiltered
                            // catalogue, so under a filter its "within 5 of the
                            // end" test almost never fires — watchalongs are
                            // scattered thinly through ~1400 items. Paging off
                            // the last *displayed* row keeps both filters going.
                            .onAppear {
                                if video.id == videos.last?.id {
                                    viewModel.loadMore()
                                } else {
                                    viewModel.loadMoreIfNeeded(current: video)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AM.Spacing.screenMargin)
                }
            }

            // Kept available for the whole filtered feed, not just an empty one:
            // watchalongs are sparse enough that the automatic trigger can stall
            // with results already on screen, and pull-to-refresh resets to page
            // one rather than continuing.
            if filter == .watchalongs, viewModel.canLoadMore {
                VideoGalleryLoadMoreFooter(
                    isLoading: viewModel.isLoading,
                    hasResults: videos.count > 1
                ) {
                    viewModel.loadMore()
                }
                .padding(.horizontal, AM.Spacing.screenMargin)
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AM.Spacing.l)
            }
        }
        .padding(.vertical, AM.Spacing.l)
    }
}

// MARK: - Filtering

enum VideoGalleryFilter: String, CaseIterable, Identifiable {
    case all
    case watchalongs

    var id: String { rawValue }

    // `String(localized:)` rather than a bare literal: `Text(someString)`
    // renders verbatim, so these segment labels and section headers were never
    // translated. Returning `LocalizedStringKey` would localize at runtime but
    // the keys would never be extracted into the catalogue — the extractor only
    // sees literals at localizable call sites, not ones handed back from a
    // computed property — so nobody could author a translation.
    var title: String {
        switch self {
        case .all: String(localized: "All Videos")
        case .watchalongs: String(localized: "Watchalongs")
        }
    }

    var sectionTitle: String {
        switch self {
        case .all: String(localized: "Recent Videos")
        case .watchalongs: String(localized: "More Watchalongs")
        }
    }

    func apply(to videos: [GalleryVideo]) -> [GalleryVideo] {
        switch self {
        case .all: videos
        case .watchalongs: videos.filter(\.isWatchalongVideo)
        }
    }
}

private struct VideoGalleryFilterBar: View {
    @Binding var filter: VideoGalleryFilter

    var body: some View {
        Picker("Filter", selection: $filter) {
            ForEach(VideoGalleryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: filter) { _, _ in
            AppHaptic.selection.play()
        }
    }
}

private struct VideoGalleryLoadMoreFooter: View {
    let isLoading: Bool
    let hasResults: Bool
    let onLoadMore: () -> Void

    var body: some View {
        VStack(spacing: AM.Spacing.m) {
            if !hasResults {
                Text("No watchalongs loaded yet")
                    .scaledSystemFont(size: 15, weight: .semibold)
                    .foregroundStyle(.primary)
            }
            Text("Watchalongs are rare in the feed. Load more of the catalogue to find them.")
                .scaledSystemFont(size: 13)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isLoading {
                ProgressView().controlSize(.regular)
            } else {
                MusicEmptyActionButton(title: "Load More") {
                    AppHaptic.selection.play()
                    onLoadMore()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AM.Spacing.xl)
    }
}

// MARK: - Cards

private struct FeaturedVideoCard: View {
    let video: GalleryVideo
    var isWatchalongFilter = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoThumbnail(video: video, cornerRadius: 14, showsBadges: false)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isWatchalongFilter ? "LATEST WATCHALONG" : "LATEST VIDEO")
                        .scaledSystemFont(size: 11, weight: .bold)
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(0.5)
                    Text(video.displayTitle)
                        .scaledSystemFont(size: 17, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let runtime = video.formattedRuntime {
                    Text(runtime)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(AM.Spacing.l)
        }
    }
}

private struct VideoGalleryCell: View {
    let video: GalleryVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoThumbnail(video: video, cornerRadius: AM.Radius.card)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.displayTitle)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let creator = video.trimmedCreator {
                    Text(creator)
                        .scaledSystemFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let views = video.views, views > 0 {
                    Text("\(VideoCountFormatter.string(from: views)) views")
                        .scaledSystemFont(size: 11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - States

private struct VideoGallerySkeleton: View {
    var body: some View {
        CenteredLoadingView(label: "Loading videos")
    }
}

private struct VideoGalleryStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onRefresh: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: AM.Spacing.xl) {
            MusicEmptyStateMark()
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.03 : 0.98))
                .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1 : 0.94))
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: AM.Spacing.s) {
                Text(title)
                    .scaledSystemFont(size: 23, weight: .bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .scaledSystemFont(size: 15)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 340)

            MusicEmptyActionButton(title: buttonTitle) {
                AppHaptic.selection.play()
                onRefresh()
            }

            VStack(spacing: AM.Spacing.s) {
                VideoGalleryHintRow(
                    title: "Karaoke videos",
                    message: "New uploads from the Twinskaraoke feed appear here."
                )
                VideoGalleryHintRow(
                    title: "Refresh the feed",
                    message: "Pull down or tap retry when the video service is slow."
                )
            }
            .frame(maxWidth: 360)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 10))
        }
        .padding(.horizontal, AM.Spacing.screenMargin)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                isPulsing = false
                return
            }
            withAnimation(AppMotion.standard) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    isPulsing = false
                    hasAppeared = true
                }
            } else {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct VideoGalleryHintRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: AM.Spacing.m) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledSystemFont(size: 14, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(message)
                    .scaledSystemFont(size: 13)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AM.Spacing.m)
        .padding(.vertical, AM.Spacing.s)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: AM.Radius.card, style: .continuous))
    }
}
