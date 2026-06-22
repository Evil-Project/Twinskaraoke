import Combine
import LNPopupUI
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
        snapshot.isPlaying
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
            await Task.yield()
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

@MainActor
final class PopupPresentationState: ObservableObject {
    static let shared = PopupPresentationState()

    // Keep popup expansion isolated from playback churn. AudioPlayerManager emits
    // frequent song, artwork, clock, and buffering updates; tying LNPopupUI's
    // expanded binding to that object makes unrelated playback/UI refreshes more
    // likely to be interpreted as presentation changes.
    @Published var isExpanded = false

    private init() {}
}

#if canImport(UIKit)
    @MainActor
    final class PopupOpenIntentGate: NSObject, UIGestureRecognizerDelegate {
        static let shared = PopupOpenIntentGate()

        private static let touchRecognizerName = "Twinskaraoke.IntentionalMiniPlayerOpen"
        private static let defaultTrailingControlHitWidth: CGFloat = 132
        private static let radioTrailingControlHitWidth: CGFloat = 192
        private static let tapMovementTolerance: CGFloat = 12
        private static let visibleBarHitHeight: CGFloat = 116
        private var touchStartLocation: CGPoint?
        private var openIntentExpiresAt = Date.distantPast
        private var suppressOpenExpiresAt = Date.distantPast

        func consumeIntent() -> Bool {
            guard Date() > suppressOpenExpiresAt else {
                openIntentExpiresAt = .distantPast
                return false
            }
            suppressOpenExpiresAt = .distantPast
            guard Date() <= openIntentExpiresAt else {
                openIntentExpiresAt = .distantPast
                return false
            }
            openIntentExpiresAt = .distantPast
            return true
        }

        func suppressNextOpen() {
            openIntentExpiresAt = .distantPast
            suppressOpenExpiresAt = Date().addingTimeInterval(0.45)
        }

        func installTouchRecognizer(on popupBar: LNPopupBar) {
            let alreadyInstalled = popupBar.gestureRecognizers?.contains {
                $0.name == Self.touchRecognizerName
            } ?? false
            guard !alreadyInstalled else { return }

            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(trackMiniPlayerTouch(_:)))
            recognizer.name = Self.touchRecognizerName
            recognizer.minimumPressDuration = 0
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            popupBar.addGestureRecognizer(recognizer)
        }

        @objc private func trackMiniPlayerTouch(_ recognizer: UILongPressGestureRecognizer) {
            guard let popupBar = recognizer.view as? LNPopupBar else { return }
            let location = recognizer.location(in: popupBar)

            switch recognizer.state {
            case .began:
                touchStartLocation = location
                guard Date() > suppressOpenExpiresAt,
                      isVisibleMiniPlayerTouch(location, in: popupBar),
                      !isTrailingControlTouch(location, in: popupBar)
                else {
                    openIntentExpiresAt = .distantPast
                    return
                }
                openIntentExpiresAt = Date().addingTimeInterval(0.45)
            case .changed:
                guard let touchStartLocation else {
                    openIntentExpiresAt = .distantPast
                    return
                }
                if distance(from: touchStartLocation, to: location) > Self.tapMovementTolerance {
                    openIntentExpiresAt = .distantPast
                }
            case .ended:
                touchStartLocation = nil
            case .cancelled, .failed:
                touchStartLocation = nil
                openIntentExpiresAt = .distantPast
            default:
                break
            }
        }

        private func isVisibleMiniPlayerTouch(_ location: CGPoint, in popupBar: LNPopupBar) -> Bool {
            let bounds = popupBar.bounds
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                return false
            }

            // LNPopupUI can keep a larger transparent gesture surface around the
            // floating bar. Treat only the visible bottom strip as a deliberate
            // mini-player touch so unrelated UI taps cannot arm a popup-open intent.
            let visibleHeight = min(bounds.height, Self.visibleBarHitHeight)
            return location.x >= bounds.minX
                && location.x <= bounds.maxX
                && location.y >= bounds.maxY - visibleHeight
                && location.y <= bounds.maxY
        }

        private func isTrailingControlTouch(_ location: CGPoint, in popupBar: LNPopupBar) -> Bool {
            let bounds = popupBar.bounds
            let controlHitWidth =
                AudioPlayerManager.shared.isRadioMode
                    ? Self.radioTrailingControlHitWidth
                    : Self.defaultTrailingControlHitWidth
            let hitWidth = min(controlHitWidth, bounds.width * 0.55)
            switch popupBar.effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                return location.x <= bounds.minX + hitWidth
            default:
                return location.x >= bounds.maxX - hitWidth
            }
        }

        private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
            hypot(end.x - start.x, end.y - start.y)
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif

struct ContentView: View {
    var body: some View {
        PopupHostView()
            .environmentObject(AudioPlayerManager.shared)
    }
}

private struct PopupHostView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var selectedSection: RootSection? = .home
    @State private var showCaptcha = false
    var body: some View {
        rootShell
            .modifier(PopupModifier())
            .onAppear {
                configureTabBarAppearance()
                applyUITestInitialSectionIfNeeded()
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
        TabView(selection: selectedTabBinding) {
            HomeView()
                .tabItem { Label(RootSection.home.title, systemImage: RootSection.home.selectedSystemImage) }
                .tag(RootSection.home)
            NewView()
                .tabItem { Label(RootSection.new.title, systemImage: RootSection.new.selectedSystemImage) }
                .tag(RootSection.new)
            RadioView()
                .tabItem { Label(RootSection.radio.title, systemImage: RootSection.radio.selectedSystemImage) }
                .tag(RootSection.radio)
            LibraryView()
                .tabItem { Label(RootSection.library.title, systemImage: RootSection.library.selectedSystemImage) }
                .tag(RootSection.library)
            SearchView()
                .tabItem { Label(RootSection.search.title, systemImage: RootSection.search.selectedSystemImage) }
                .tag(RootSection.search)
        }
        .tint(.appAccent)
    }

    private var sidebarShell: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(RootSectionGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            SidebarSectionRow(section: section, isSelected: currentSection == section)
                                .tag(Optional(section))
                                .accessibilityIdentifier(section.sidebarAccessibilityIdentifier)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Twinskaraoke")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarNowPlayingHint()
            }
        } detail: {
            currentSection.content
                .id(currentSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(shellTransition)
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
        reduceMotion ? nil : AppMotion.spring(response: 0.24, dampingFraction: 0.88)
    }

    private var shellTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
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

    private func applyUITestInitialSectionIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-UITestInitialSection"),
              arguments.indices.contains(flagIndex + 1),
              let section = RootSection(rawValue: arguments[flagIndex + 1].lowercased())
        else {
            return
        }
        selectedSection = section
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

    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .new: "square.grid.2x2.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
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
                Image(systemName: isSelected ? section.selectedSystemImage : section.systemImage)
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

private struct PopupModifier: ViewModifier {
    @ObservedObject private var popupState = PopupPlaybackState.shared
    @ObservedObject private var presentationState = PopupPresentationState.shared

    func body(content: Content) -> some View {
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
                                    presentationState.isExpanded = false
                                    return
                                }
                            #endif
                        }
                        presentationState.isExpanded = isOpen
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
