import Combine
import LNPopupUI
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Playback State

@MainActor
private final class PopupPlaybackState: ObservableObject {
    static let shared = PopupPlaybackState()

    var hasCurrentSong: Bool {
        snapshot.id != nil
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
        snapshot.isPlaying || (snapshot.isRadioMode && snapshot.isBuffering)
    }

    var isRadioMode: Bool {
        snapshot.isRadioMode
    }

    @Published private var snapshot = PopupPlaybackSnapshot()
    private var pendingSnapshot = PopupPlaybackSnapshot()
    private var publishTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let manager = AudioPlayerManager.shared
        manager.$currentSong
            .removeDuplicates(by: {
                $0?.id == $1?.id
                    && $0?.title == $1?.title
                    && $0?.displayArtist == $1?.displayArtist
            })
            .sink { [weak self] song in
                self?.updatePendingSnapshot { snapshot in
                    snapshot.id = song?.id
                    snapshot.title = song?.title ?? ""
                    snapshot.subtitle = song?.displayArtist ?? ""
                }
            }
            .store(in: &cancellables)

        manager.$nowPlayingArtwork
            .removeDuplicates(by: { $0 === $1 })
            .sink { [weak self] artwork in
                self?.updatePendingSnapshot { snapshot in
                    snapshot.artwork = artwork
                }
            }
            .store(in: &cancellables)

        manager.$isPlaying
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.updatePendingSnapshot { snapshot in
                    snapshot.isPlaying = isPlaying
                }
            }
            .store(in: &cancellables)

        manager.$isBuffering
            .removeDuplicates()
            .sink { [weak self] isBuffering in
                self?.updatePendingSnapshot { snapshot in
                    snapshot.isBuffering = isBuffering
                }
            }
            .store(in: &cancellables)

        manager.$isRadioMode
            .removeDuplicates()
            .sink { [weak self] isRadioMode in
                self?.updatePendingSnapshot { snapshot in
                    snapshot.isRadioMode = isRadioMode
                }
            }
            .store(in: &cancellables)
    }

    private func updatePendingSnapshot(_ update: (inout PopupPlaybackSnapshot) -> Void) {
        update(&pendingSnapshot)
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
    var isBuffering = false
    var isRadioMode = false

    func matches(_ other: PopupPlaybackSnapshot) -> Bool {
        id == other.id
            && title == other.title
            && subtitle == other.subtitle
            && artwork === other.artwork
            && isPlaying == other.isPlaying
            && isBuffering == other.isBuffering
            && isRadioMode == other.isRadioMode
    }
}

// MARK: - Root Views

struct ContentView: View {
    var body: some View {
        PopupHostView()
            .environmentObject(AudioPlayerManager.shared)
    }
}

private struct PopupHostView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var searchState = SearchRootState()
    @State private var selectedSection: RootSection? = RootSection.launchSelection
    @State private var shellMode: RootShellMode?
    @State private var shellTransitionGeneration = 0
    @State private var showCaptcha = false

    var body: some View {
        rootShell
            .modifier(PopupModifier())
            .onAppear {
                searchState.isSelected = currentSection == .search
                configureTabBarAppearance()
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
            let desiredMode = rootShellMode(availableWidth: proxy.size.width)
            let activeMode = shellMode ?? desiredMode
            ZStack(alignment: .leading) {
                rootTabs
                    .padding(.leading, activeMode == .sidebar ? 321 : 0)
                    .toolbar(activeMode == .sidebar ? .hidden : .visible, for: .tabBar)

                if activeMode == .sidebar {
                    sidebar
                        .transition(.identity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                shellMode = desiredMode
            }
            .onChange(of: desiredMode) { _, newMode in
                transitionShell(to: newMode)
            }
        }
    }

    private func rootShellMode(availableWidth: CGFloat) -> RootShellMode {
        guard AM.Layout.usesWideCanvas(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: availableWidth
        ) else { return .tabs }
        #if canImport(UIKit)
            let idiom = UIDevice.current.userInterfaceIdiom
            return idiom == .pad || idiom == .mac ? .sidebar : .tabs
        #else
            return .sidebar
        #endif
    }

    private var rootTabs: some View {
        RootSectionTabs(selection: selectedTabBinding, searchState: searchState)
            .tint(.appAccent)
    }

    private var sidebar: some View {
        HStack(spacing: 0) {
            NavigationStack {
                List(selection: sidebarSelectionBinding) {
                    ForEach(RootSectionGroup.allCases) { group in
                        Section(group.title) {
                            ForEach(group.sections) { section in
                                Button {
                                    selectSection(section)
                                } label: {
                                    SidebarSectionRow(section: section, isSelected: currentSection == section)
                                }
                                .buttonStyle(.plain)
                                .tag(Optional(section))
                                .accessibilityIdentifier(section.sidebarAccessibilityIdentifier)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Twinskaraoke")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    SidebarNowPlayingHint()
                }
            }
            .frame(width: 320)

            Divider()
        }
        .frame(width: 321)
        .frame(maxHeight: .infinity)
        .background(Color.appBackground)
        .tint(.appAccent)
    }

    private var selectedTabBinding: Binding<RootSection> {
        Binding(
            get: { currentSection },
            set: { newSection in
                selectSection(newSection)
            }
        )
    }

    private var sidebarSelectionBinding: Binding<RootSection?> {
        Binding(
            get: { selectedSection },
            set: { newSection in
                selectSection(newSection ?? .home)
            }
        )
    }

    private var currentSection: RootSection {
        selectedSection ?? .home
    }

    private func selectSection(_ section: RootSection) {
        if currentSection != section {
            AppHaptic.selection.play()
        }
        searchState.isSelected = section == .search
        selectedSection = section
    }

    private func transitionShell(to newMode: RootShellMode) {
        guard shellMode != newMode else { return }
        shellTransitionGeneration += 1
        let generation = shellTransitionGeneration
        searchState.isShellTransitioning = true
        shellMode = newMode

        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard shellTransitionGeneration == generation else { return }
            searchState.isShellTransitioning = false
        }
    }

    private func configureTabBarAppearance() {
        #if canImport(UIKit)
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
            UITabBar.appearance().isTranslucent = true
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

}

private enum RootShellMode: Equatable {
    case tabs
    case sidebar
}

private struct RootSectionTabs: View {
    @Binding var selection: RootSection
    @ObservedObject var searchState: SearchRootState

    var body: some View {
        TabView(selection: $selection) {
            ForEach(RootSection.allCases) { section in
                RootSectionDestination(section: section, searchState: searchState)
                    .tabItem {
                        Label(section.title, systemImage: section.selectedSystemImage)
                    }
                    .tag(section)
            }
        }
    }
}

private struct RootSectionDestination: View {
    let section: RootSection
    @ObservedObject var searchState: SearchRootState

    @ViewBuilder
    var body: some View {
        switch section {
        case .home:
            HomeView()
        case .new:
            NewView()
        case .radio:
            RadioView()
        case .library:
            LibraryView()
        case .search:
            SearchView(state: searchState)
        }
    }
}

// MARK: - App Navigation Enums

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

    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .new: "square.grid.2x2.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }

}

private extension RootSection {
    static var launchSelection: RootSection {
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

// MARK: - Sidebar Helper Views

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
                Image(systemName: isSelected ? section.selectedSystemImage : section.systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? Color.white : section.sidebarTint)
            }
            .frame(width: 25, height: 25)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
    }
}

private struct SidebarNowPlayingHint: View {
    @ObservedObject private var popupState = PopupPlaybackState.shared

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
                .background(.bar)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now Playing")
                .accessibilityValue(popupState.subtitle.isEmpty ? popupState.title : "\(popupState.title), \(popupState.subtitle)")
            }
        }
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

// MARK: - LNPopupUI Modifiers & iOS 27 Fallback

private enum SystemCompatibility {
    static var isIOS27OrNewer: Bool {
        guard #available(iOS 27, *) else { return false }
        return true
    }
}

private struct PopupModifier: ViewModifier {
    @ObservedObject private var popupState = PopupPlaybackState.shared
    @ObservedObject private var presentationState = PopupPresentationState.shared

    func body(content: Content) -> some View {
        Group {
            if SystemCompatibility.isIOS27OrNewer {
                // iOS 27 Beta Safe Fallback Layout
                content
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if popupState.hasCurrentSong {
                            iOS27FallbackMiniPlayer
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                        }
                    }
                    .sheet(isPresented: Binding(
                        get: { presentationState.isExpanded },
                        set: { presentationState.setExpanded($0) }
                    )) {
                        FullScreenPlayerView()
                            .environmentObject(AudioPlayerManager.shared)
                    }
            } else {
                // Stable LNPopupUI Native Layout
                content
                    .popup(
                        isBarPresented: .constant(popupState.hasCurrentSong),
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
                                presentationState.setExpanded(isOpen)
                            }
                        )
                    ) {
                        PopupContent(popupState: popupState)
                    }
                    .popupBarStyle(.floating)
                    .popupBarProgressViewStyle(.none)
                    .popupCloseButtonStyle(.none)
                    .popupInteractionStyle(.drag)
                    .popupBarMarqueeScrollEnabled(false)
                    .popupBarCustomizer { popupBar in
                        popupBar.accessibilityIdentifier = "MiniPlayerBar"
                        popupBar.accessibilityLabel = "Now Playing"
                        popupBar.accessibilityHint = "Opens the full-screen player."
                        PopupOpenIntentGate.shared.installTouchRecognizer(on: popupBar)
                    }
            }
        }
    }

    // Custom iOS 27 Fallback Mini Player (Styled exactly like the original floating player)
    @ViewBuilder
    private var iOS27FallbackMiniPlayer: some View {
        HStack(spacing: 12) {
            Button {
                presentationState.setExpanded(true)
            } label: {
                HStack(spacing: 12) {
                    if let artwork = popupState.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    } else {
                        MusicArtworkPlaceholder(cornerRadius: 6)
                            .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(popupState.title)
                            .font(.headline)
                            .lineLimit(1)
                        if !popupState.subtitle.isEmpty {
                            Text(popupState.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Now Playing")
            .accessibilityValue(
                popupState.subtitle.isEmpty
                    ? popupState.title
                    : "\(popupState.title), \(popupState.subtitle)"
            )
            .accessibilityHint("Opens the full-screen player.")

            PopupBarTrailingItems(
                isPlaying: popupState.isPlaying,
                isRadioMode: popupState.isRadioMode,
                onTogglePlayPause: {
                    AudioPlayerManager.shared.togglePlayPause()
                },
                onNext: {
                    AudioPlayerManager.shared.playNextOrRandom()
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Replicate the floating LNPopupUI pill style
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

private struct PopupContent: View {
    @ObservedObject private var popupState: PopupPlaybackState

    init(popupState: PopupPlaybackState) {
        self.popupState = popupState
    }

    var body: some View {
        FullScreenPlayerView()
            .environmentObject(AudioPlayerManager.shared)
            .modifier(
                PopupTitleModifier(
                    title: popupState.title,
                    subtitle: popupState.subtitle
                )
            )
            .modifier(PopupImageModifier(artwork: popupState.artwork))
            .popupBarButtons {
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

private struct PopupTitleModifier: ViewModifier, Equatable {
    let title: String
    let subtitle: String
    func body(content: Content) -> some View {
        content.popupTitle(title, subtitle: subtitle)
    }
}

private struct PopupImageModifier: ViewModifier, Equatable {
    let artwork: UIImage?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.artwork === rhs.artwork
    }

    func body(content: Content) -> some View {
        if let artwork {
            content.popupImage(Image(uiImage: artwork))
        } else {
            content.popupImage(Image(systemName: "music.note"))
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
                Group {
                    if #available(iOS 17.0, *) {
                        Image(systemName: playPauseSymbol)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: playPauseSymbol)
                            .contentTransition(.opacity)
                    }
                }
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .medium))
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
                .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .light))
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
