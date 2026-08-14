import SwiftUI
import Observation

#if canImport(UIKit)
    import UIKit
#endif

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
    private let nowPlaying = NowPlayingSnapshotState.shared
    // The mini player is presented from the root and sits above every pushed
    // screen, so `.toolbar(.hidden, for: .tabBar)` cannot reach it — a
    // full-screen video has to withdraw the bar here instead.
    private let videoFullScreen = VideoFullScreenState.shared

    init() {
        _selectedSection = State(initialValue: Self.initialSection)
    }

    var body: some View {
        // The reader is outside the overlay on purpose: it is laid out
        // normally, so it can still see the window's safe-area insets. The
        // overlay ignores them, and nothing nested under that point can read
        // them back.
        GeometryReader { proxy in
            ZStack {
                rootShell
                NowPlayingOverlay(safeAreaInsets: proxy.safeAreaInsets)
            }
        }
        .environment(homeViewModel)
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

    /// The mini player shows whenever there is something playing, and steps
    /// aside for full-screen video, which covers the tab bar the accessory
    /// slot lives in.
    private var showsMiniPlayer: Bool {
        nowPlaying.hasCurrentSong && !videoFullScreen.isActive
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
        // The mini player goes in the system's own accessory slot — the one
        // Apple Music uses. That is what gives it Liquid Glass, the merge into
        // the minimized tab bar, and a bottom content inset on every screen
        // underneath, none of which we now maintain ourselves.
        .tabViewBottomAccessory(isEnabled: showsMiniPlayer) {
            MiniPlayerBar()
        }
        // UIKit owns minimizing and revealing, in both directions.
        //
        // `TabBarMinimizeCoordinator` used to drive the reveal off a shorter
        // threshold by flipping this to `.never` and back, because the system's
        // own reveal distance is long — measured at roughly 440pt. That flip was
        // the thing making the mini player misbehave: forced, the accessory took
        // its expanded frame, fell back to the inline one, and corrected only
        // when minimization was handed back, so the pill sat at the wrong width
        // for as long as that took. Left alone, every transition is a single
        // clean change between x=84 w=234 and x=21 w=360.
        //
        // LNPopupController reached the same conclusion from the other side: it
        // reads the tab bar's minimized state and its proposed accessory frame
        // and follows them. It never drives the bar. We have no private API and
        // no need for one — we just stop pushing.
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
            //
            // The same `MiniPlayerBar` as the tab shell, not a second design.
            // There is no accessory slot outside a `TabView`, so it reads a nil
            // placement and lays itself out at full size. This used to be a
            // separate, non-interactive "Now Playing" hint that sat *underneath*
            // a floating popup bar — two mini players stacked on the same screen.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if showsMiniPlayer {
                    MiniPlayerBar()
                        .padding(.vertical, 8)
                        .transition(.opacity)
                }
            }
            .animation(AppMotion.quick, value: showsMiniPlayer)
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

#Preview {
    ContentView()
}
