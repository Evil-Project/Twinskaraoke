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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var homeViewModel = HomeViewModel()
    @State private var selectedSection: RootSection?
    @State private var showCaptcha = false
    private let nowPlaying = NowPlayingSnapshotState.shared
    private let videoFullScreen = VideoFullScreenState.shared

    init() {
        _selectedSection = State(initialValue: AppRouter.shared.hasPendingRoute ? AppRouter.shared.section : Self.initialSection)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                rootShell
                NowPlayingOverlay(safeAreaInsets: proxy.safeAreaInsets)
            }
        }
        .environment(homeViewModel)
        .background(MiniPlayerGesture())
        #if DEBUG
        .background {
            if ProcessInfo.processInfo.arguments.contains("-UITestPlayerGestureCompetition") {
                PlayerGestureCompetitionProbe()
            }
        }
        #endif
        .onChange(of: AppRouter.shared.requestID) { _, _ in
            selectedSection = AppRouter.shared.section
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            AppRouter.shared.open(route)
            selectedSection = AppRouter.shared.section
        }
        .sheet(isPresented: Binding(
            get: { AppRouter.shared.detail != nil },
            set: { if !$0 { AppRouter.shared.dismissDetail() } }
        ), onDismiss: { AppRouter.shared.resumeAfterSplash() }) {
            NavigationStack {
                if let route = AppRouter.shared.detail {
                    RoutedDetailView(route: route)
                        // A second link while the sheet is up replaces the
                        // route in place; a fresh identity drops the previous
                        // route's loaded song or playlist instead of showing
                        // it until the new one arrives.
                        .id(route.url)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { AppRouter.shared.dismissDetail() } } }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WidgetSnapshotPublisher.shared.publish()
                WidgetSnapshotPublisher.shared.refreshLibrarySuggestions()
                AudioPlayerManager.shared.sleepTimer.checkExpiry()
                homeViewModel.retryIfLoadFailed()
                DownloadManager.shared.retryRestoration()
                FavoritesManager.shared.loadIfNeeded()
                UserPlaylistsManager.shared.loadIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            DownloadManager.shared.retryRestoration()
            FavoritesManager.shared.loadIfNeeded()
            UserPlaylistsManager.shared.loadIfNeeded()
        }
        .onAppear {
            FavoritesManager.shared.loadIfNeeded()
            UserPlaylistsManager.shared.loadIfNeeded()
            if !AppRuntime.isUITestMode && DeveloperMode.shouldTriggerEasterEgg() {
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
        guard AM.Layout.usesSidebarCanvas(
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
        RootTabShell(selection: selectedTabBinding, showsAccessory: showsMiniPlayer) { section in
            section.content
        } accessory: {
            MiniPlayerBar()
        }
    }

    private var sidebarShell: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(RootSectionGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            SidebarSectionRow(section: section, isSelected: currentSection == section)
                                .tag(section)
                                .accessibilityIdentifier(section.sidebarAccessibilityIdentifier)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Twinskaraoke")
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

/// Shared root tab configuration, hosted independently by regression tests.
struct RootTabShell<Content: View, Accessory: View>: View {
    @Binding var selection: RootSection
    var showsAccessory: Bool
    @ViewBuilder var content: (RootSection) -> Content
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        // Driven off `allCases` and `content` so the enum stays the only place
        // a section is described — the sidebar already builds itself the same
        // way, and listing the screens here too let the two drift apart.
        //
        // `systemImage` is the unfilled symbol: the tab bar fills it for the
        // selected tab itself. Passing the filled variant is what made Home and
        // New render filled even while unselected.
        TabView(selection: $selection) {
            ForEach(RootSection.allCases) { section in
                Tab(
                    section.title,
                    systemImage: section.systemImage,
                    value: section,
                    role: section.tabRole
                ) {
                    content(section)
                }
            }
        }
        .tint(.appAccent)
        // Declare activation in SwiftUI so tab rebuilds preserve the separate
        // Search button instead of resetting an underlying UIKit assignment.
        .tabViewSearchActivation(.searchTabSelection)
        // The mini player goes in the system's own accessory slot — the one
        // Apple Music uses. That is what gives it Liquid Glass, the merge into
        // the minimized tab bar, and a bottom content inset on every screen
        // underneath, none of which we now maintain ourselves.
        .tabViewBottomAccessory(isEnabled: showsAccessory) {
            accessory()
        }
        // The system owns minimization entirely. A short-scroll-up reveal was
        // built on top of this once, by flipping the policy to `.never` to
        // force an expansion; iOS 27 applies that flip with no transition at
        // all, and no API exists to ask for one. Apple Music, Pocket Casts and
        // every comparable app restore at the scroll edge, which is what this
        // does now.
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

enum RootSection: String, CaseIterable, Identifiable {
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
        case .home: String(localized: "Home")
        case .new: String(localized: "New")
        case .radio: String(localized: "Radio")
        case .library: String(localized: "Library")
        case .search: String(localized: "Search")
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
        case .discover: String(localized: "Discover")
        case .collection: String(localized: "Collection")
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
    var sidebarSelectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .new: "square.grid.2x2.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }

    /// A website theme tints every section in its primary, as the site's own
    /// sidebar does; next to it the fixed purple, orange, blue and green
    /// below would clash. Every other theme keeps one colour per section.
    var sidebarTint: Color {
        if let primary = AppThemeStore.shared.palette?.primary { return primary }
        return switch self {
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
