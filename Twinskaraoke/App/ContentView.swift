import Combine
import LNPopupUI
import SwiftUI
import Observation

#if canImport(UIKit)
    import UIKit
#endif

@MainActor
@Observable
private final class PopupPlaybackState {
    static let shared = PopupPlaybackState()

    var hasCurrentSong: Bool {
        snapshot.id != nil
    }

    var id: String {
        snapshot.id ?? "now-playing"
    }

    var title: String {
        snapshot.title
    }

    var subtitle: String {
        snapshot.subtitle
    }

    var artwork: UIImage? {
        snapshot.artwork
    }

    var isPlaying: Bool {
        snapshot.isPlaying
    }

    var isRadioMode: Bool {
        snapshot.isRadioMode
    }

    private var snapshot = PopupPlaybackSnapshot()
    @ObservationIgnored private var pendingSnapshot = PopupPlaybackSnapshot()
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var observation: ObservationToken?

    private init() {
        // Replaces four `$property.sink` pipelines. The per-property
        // `removeDuplicates` they carried is redundant here: `scheduleSnapshotPublish`
        // already drops a rebuild that `matches` the published snapshot, so
        // rebuilding all four fields on any change is equivalent.
        observation = observeContinuously({
            let manager = AudioPlayerManager.shared
            _ = manager.currentSong
            _ = manager.nowPlayingArtwork
            _ = manager.isPlaying
            _ = manager.isRadioMode
        }, onChange: { [weak self] in
            self?.rebuildPendingSnapshot()
        })
        rebuildPendingSnapshot()
    }

    private func rebuildPendingSnapshot() {
        let manager = AudioPlayerManager.shared
        let song = manager.currentSong
        pendingSnapshot.id = song?.id
        pendingSnapshot.title = song?.title ?? ""
        pendingSnapshot.subtitle = song?.displayArtist ?? ""
        pendingSnapshot.artwork = manager.nowPlayingArtwork
        pendingSnapshot.isPlaying = manager.isPlaying
        pendingSnapshot.isRadioMode = manager.isRadioMode
        scheduleSnapshotPublish()
    }

    private func scheduleSnapshotPublish() {
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard let self else { return }
            let nextSnapshot = pendingSnapshot
            publishTask = nil
            guard !snapshot.matches(nextSnapshot) else { return }

            snapshot = nextSnapshot
        }
    }
}

private struct PopupPlaybackSnapshot {
    var id: String?
    var title = ""
    var subtitle = ""
    var artwork: UIImage?
    var isPlaying = false
    var isRadioMode = false

    func matches(_ other: PopupPlaybackSnapshot) -> Bool {
        id == other.id
            && title == other.title
            && subtitle == other.subtitle
            && artwork === other.artwork
            && isPlaying == other.isPlaying
            && isRadioMode == other.isRadioMode
    }
}

struct ContentView: View {
    var body: some View {
        PopupHostView()
            .environment(AudioPlayerManager.shared)
    }
}

private struct PopupHostView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var homeViewModel = HomeViewModel()
    @State private var selectedSection: RootSection?
    @State private var showCaptcha = false

    init() {
        _selectedSection = State(initialValue: Self.initialSection)
    }

    var body: some View {
        rootShell
            .environment(homeViewModel)
            .modifier(PopupModifier())
            .onAppear {
                // Warm the account-scoped state that the shared song context
                // menu reads. Both used to load only when Library (or the
                // full-screen player) first appeared, so a long-press before
                // that — or during the fetch — rendered "Favorite" for a song
                // that was already favorited, and hid "Remove from Playlist".
                // A context menu's contents are snapshotted when it opens, so a
                // load landing mid-press cannot correct the label afterwards.
                FavoritesManager.shared.loadIfNeeded()
                UserPlaylistsManager.shared.loadIfNeeded()
                if DeveloperMode.shouldTriggerEasterEgg() {
                    showCaptcha = true
                }
            }
            .fullScreenCover(isPresented: $showCaptcha) {
                CaptchaWebView(
                    url: URL(string: "https://twinskaraoke.evilneur.org")!,
                    onClose: { showCaptcha = false }
                )
                .ignoresSafeArea()
            }
    }

    private var rootShell: some View {
        GeometryReader { proxy in
            Group {
                if usesSidebarShell(availableWidth: proxy.size.width) {
                    sidebarShell
                } else {
                    rootTabs
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func usesSidebarShell(availableWidth: CGFloat) -> Bool {
        guard AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) else { return false }
        #if canImport(UIKit)
            let idiom = UIDevice.current.userInterfaceIdiom
            return idiom == .pad || idiom == .mac
        #else
            return true
        #endif
    }

    private var rootTabs: some View {
        // Driven off `allCases` and `content` so the enum stays the only place
        // a section is described — the sidebar already builds itself the same
        // way, and listing the screens here too let the two drift apart.
        //
        // `systemImage` is the unfilled symbol: the tab bar fills it for the
        // selected tab itself. Passing the filled variant is what made Home and
        // New render filled even while unselected.
        TabView(selection: selectedTabBinding) {
            ForEach(RootSection.allCases) { section in
                Tab(
                    section.title,
                    systemImage: section.systemImage,
                    value: section,
                    role: section.tabRole
                ) {
                    section.content
                }
            }
        }
        .tint(.appAccent)
        // Replaces the hand-rolled scroll-collapse that BottomChromeState was
        // built for and never wired up. Worth re-checking on device if the
        // mini player ever looks misplaced: LNPopupController floats its bar
        // above the tab bar, and ShimejiFloorRegistry rests idle instances on
        // the live UITabBar's top edge, both of which move as the bar minimizes.
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var sidebarShell: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(RootSectionGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            SidebarSectionRow(section: section, isSelected: currentSection == section)
                                // `List(selection: Binding<RootSection?>)` matches rows by a tag
                                // whose type is RootSection — a `RootSection?` tag never matches,
                                // leaving every row unselectable (taps highlight, nothing happens).
                                .tag(section)
                                .accessibilityIdentifier(section.sidebarAccessibilityIdentifier)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Twinskaraoke")
            // `safeAreaBar`, not `safeAreaInset`: this is a bar, so it should
            // get the bar treatment — glass and scroll-edge behaviour — rather
            // than painting its own `.bar` background under a plain inset.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                SidebarNowPlayingHint()
            }
        } detail: {
            currentSection.content
                .id(currentSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.appAccent)
        .animation(shellAnimation, value: currentSection)
        .onChange(of: selectedSection) { _, newValue in
            if newValue == nil {
                selectedSection = .home
            } else {
                AppHaptic.selection.play()
            }
        }
    }

    private var selectedTabBinding: Binding<RootSection> {
        Binding(
            get: { currentSection },
            set: { newSection in
                if selectedSection != newSection {
                    AppHaptic.selection.play()
                }
                selectedSection = newSection
            }
        )
    }

    private var currentSection: RootSection {
        selectedSection ?? .home
    }

    private var shellAnimation: Animation? {
        reduceMotion ? nil : AppMotion.snap
    }

    private static var initialSection: RootSection {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-UITestInitialSection"),
              arguments.indices.contains(flagIndex + 1),
              let section = RootSection(rawValue: arguments[flagIndex + 1].lowercased())
        else {
            return .home
        }
        return section
    }
}

private enum RootSection: String, CaseIterable, Identifiable {
    case home
    case new
    case radio
    case library
    case search

    var id: String {
        rawValue
    }

    var sidebarAccessibilityIdentifier: String {
        "RootSection.\(rawValue)"
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .new: "New"
        case .radio: "Radio"
        case .library: "Library"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .new: "square.grid.2x2"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }

    /// Search gets the system's search affordance on iOS 26 — separated from
    /// the rest of the bar, and morphing into the search field rather than
    /// pushing a screen that happens to contain one. Everything else is an
    /// ordinary tab.
    var tabRole: TabRole? {
        self == .search ? .search : nil
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .home:
            HomeView()
        case .new:
            NewView()
        case .radio:
            RadioView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        }
    }
}

private enum RootSectionGroup: String, CaseIterable, Identifiable {
    case discover
    case collection

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .collection: "Collection"
        }
    }

    var sections: [RootSection] {
        switch self {
        case .discover: [.home, .new, .radio, .search]
        case .collection: [.library]
        }
    }
}

private struct SidebarSectionRow: View {
    let section: RootSection
    let isSelected: Bool

    var body: some View {
        Label {
            Text(section.title)
                .font(isSelected ? .headline : .body)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(section.sidebarTint.opacity(isSelected ? 1 : 0.14))
                Image(systemName: isSelected ? section.sidebarSelectedSystemImage : section.systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? Color.white : section.sidebarTint)
            }
            .frame(width: 25, height: 25)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
    }
}

private struct SidebarNowPlayingHint: View {
    private let popupState = PopupPlaybackState.shared

    var body: some View {
        Group {
            if popupState.hasCurrentSong {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now Playing")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(popupState.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !popupState.subtitle.isEmpty {
                            Text(popupState.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // No background or hairline of its own — `safeAreaBar` gives the
                // content the system bar treatment, and painting `.bar` plus a
                // divider on top of that just doubles it.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now Playing")
                .accessibilityValue(popupState.subtitle.isEmpty ? popupState.title : "\(popupState.title), \(popupState.subtitle)")
                .transition(.opacity)
            }
        }
        .animation(AppMotion.quick, value: popupState.hasCurrentSong)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = popupState.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
        } else {
            MusicArtworkPlaceholder(cornerRadius: AM.Radius.thumb)
                .frame(width: 38, height: 38)
        }
    }
}

private extension RootSection {
    /// Sidebar only, and deliberately scoped to this extension: the tab bar
    /// fills the selected symbol for itself, and handing it the filled variant
    /// is what previously made Home and New render filled while unselected.
    ///
    /// Radio, Library and Search repeat their unselected symbol because
    /// `dot.radiowaves.left.and.right`, `music.note.list` and `magnifyingglass`
    /// have no filled counterpart in SF Symbols. The sidebar still reads as
    /// selected: `SidebarSectionRow` swaps the icon's tinted backing plate to
    /// full opacity and its foreground to white.
    var sidebarSelectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .new: "square.grid.2x2.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }

    var sidebarTint: Color {
        switch self {
        case .home:
            .appAccent
        case .new:
            Color(red: 0.63, green: 0.34, blue: 0.98)
        case .radio:
            Color(red: 0.98, green: 0.42, blue: 0.18)
        case .library:
            Color(red: 0.18, green: 0.58, blue: 0.98)
        case .search:
            Color(red: 0.23, green: 0.68, blue: 0.48)
        }
    }
}

private struct PopupModifier: ViewModifier {
    private let popupState = PopupPlaybackState.shared
    private let presentationState = PopupPresentationState.shared
    private let barEnvironment = PopupBarEnvironmentTracker.shared
    // LNPopupController floats the mini player above the tab bar and every
    // pushed screen, so `.toolbar(.hidden, for: .tabBar)` cannot reach it — a
    // full-screen video has to withdraw the bar here instead.
    private let videoFullScreen = VideoFullScreenState.shared

    func body(content: Content) -> some View {
        content
            .popup(
                isBarPresented: .constant(popupState.hasCurrentSong && !videoFullScreen.isActive),
                isPopupOpen: Binding(
                    get: { presentationState.isExpanded },
                    set: { isOpen in
                        if isOpen {
                            #if canImport(UIKit)
                                let isIntentionalOpen =
                                    presentationState.isExpanded || PopupOpenIntentGate.shared.consumeIntent()
                                guard isIntentionalOpen else {
                                    presentationState.collapse()
                                    return
                                }
                            #endif
                        }
                        // The mini player's own tap and its swipe-to-dismiss are
                        // handled inside LNPopupController, so this binding is
                        // the only place either surfaces to us.  Guarded on an
                        // actual change: the suppression path above calls
                        // `collapse()` on an already-collapsed popup.
                        let wasExpanded = presentationState.isExpanded
                        presentationState.setExpanded(isOpen)
                        if isOpen != wasExpanded {
                            (isOpen ? AppHaptic.commit : AppHaptic.dismiss).play()
                        }
                    }
                )
            ) {
                PopupContent(popupState: popupState)
            }
            // `.floating` (58pt) matches the full-size tab bar; `.floatingCompact`
            // (48pt) matches the minimized row the bar merges into. The height
            // comes from the style alone — LNPopupController does not shrink a
            // bar when it goes inline — so the style has to follow the tab bar,
            // which is what PopupBarEnvironmentTracker watches for.
            //
            // The artwork follows the height on its own: LNPopupBar sizes it as
            // `barHeight - 18`, so it moves between 40pt and 30pt with the bar.
            .popupBarStyle(barEnvironment.barStyle)
            .popupBarProgressViewStyle(.none)
            .popupCloseButtonStyle(.none)
            .popupInteractionStyle(.drag)
            .popupBarMarqueeScrollEnabled(false)
            .popupBarCustomizer { popupBar in
                popupBar.accessibilityIdentifier = "MiniPlayerBar"
                popupBar.accessibilityLabel = "Now Playing"
                popupBar.accessibilityHint = "Opens the full-screen player."

                PopupOpenIntentGate.shared.installTouchRecognizer(on: popupBar)
                #if canImport(UIKit)
                    PopupBarEnvironmentTracker.shared.observe(popupBar)
                    ShimejiMiniPlayerTracker.shared.register(popupBar)
                #endif
            }
    }
}

private struct PopupContent: View {
    private let popupState: PopupPlaybackState

    init(popupState: PopupPlaybackState) {
        self.popupState = popupState
    }

    var body: some View {
        FullScreenPlayerView()
            .environment(AudioPlayerManager.shared)
            .popupItem {
                PopupItem(
                    id: popupState.id,
                    verbatimTitle: popupState.title,
                    verbatimSubtitle: popupState.subtitle.isEmpty ? nil : popupState.subtitle,
                    image: popupImage
                ) {
                    ToolbarItemGroup(placement: .popupBar) {
                        PopupBarTrailingItems(
                            isPlaying: popupState.isPlaying,
                            isRadioMode: popupState.isRadioMode,
                            onTogglePlayPause: {
                                #if canImport(UIKit)
                                    PopupOpenIntentGate.shared.suppressNextOpen()
                                #endif
                                AudioPlayerManager.shared.togglePlayPause()
                            },
                            onNext: {
                                #if canImport(UIKit)
                                    PopupOpenIntentGate.shared.suppressNextOpen()
                                #endif
                                AudioPlayerManager.shared.playNextOrRandom()
                            }
                        )
                    }
                }
            }
    }

    private var popupImage: Image {
        if let artwork = popupState.artwork {
            Image(uiImage: artwork)
        } else {
            Image(systemName: "music.note")
        }
    }
}

private struct PopupBarTrailingItems: View, Equatable {
    let isPlaying: Bool
    let isRadioMode: Bool
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPlaying == rhs.isPlaying && lhs.isRadioMode == rhs.isRadioMode
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onTogglePlayPause) {
                Image(systemName: playPauseSymbol)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .commit))
            .accessibilityLabel(playPauseAccessibilityLabel)
            .accessibilityHint(
                isRadioMode ? "Controls the live radio stream." : "Controls the current song."
            )
            if !isRadioMode {
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .selection))
                .accessibilityLabel("Next track")
                .accessibilityHint("Skips to the next song.")
            }
        }
    }

    private var playPauseAccessibilityLabel: String {
        if isRadioMode {
            return isPlaying ? "Stop live radio" : "Play live radio"
        }
        return isPlaying ? "Pause" : "Play"
    }

    private var playPauseSymbol: String {
        if isRadioMode {
            return isPlaying ? "stop.fill" : "play.fill"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }
}

#Preview {
    ContentView()
}
