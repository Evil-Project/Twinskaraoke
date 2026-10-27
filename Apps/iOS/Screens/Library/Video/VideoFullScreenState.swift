import Observation
import SwiftUI

/// Whether a video is currently filling the screen.
///
/// The tab bar (and the search button, which is a `role: .search` tab) hides
/// itself per-screen via `.toolbar(.hidden, for: .tabBar)`. The LNPopup mini
/// player cannot: it is presented from the root in `ContentView` and floats
/// above everything, so it needs a global signal to step out of the way.
///
/// Counted rather than stored as a flag, for the same reason as
/// `AppOrientationGate`: pushing a video from the "Similar Videos" list leaves
/// the previous screen alive until the transition settles, and a Boolean would
/// let the disappearing screen clear the state for the one that just appeared.
@MainActor
@Observable
final class VideoFullScreenState {
    static let shared = VideoFullScreenState()

    private var activeCount = 0

    private init() {}

    var isActive: Bool { activeCount > 0 }

    func update(isActive: Bool) {
        activeCount = max(0, activeCount + (isActive ? 1 : -1))
    }
}

extension View {
    /// Publishes this screen's full-screen state so root-level chrome can hide.
    func videoFullScreenState(_ isFullScreen: Bool) -> some View {
        modifier(VideoFullScreenStateModifier(isFullScreen: isFullScreen))
    }
}

private struct VideoFullScreenStateModifier: ViewModifier {
    let isFullScreen: Bool
    @State private var isRegistered = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isFullScreen, initial: true) { _, isFullScreen in
                sync(to: isFullScreen)
            }
            .onDisappear { sync(to: false) }
    }

    private func sync(to isFullScreen: Bool) {
        guard isFullScreen != isRegistered else { return }
        isRegistered = isFullScreen
        VideoFullScreenState.shared.update(isActive: isFullScreen)
    }
}
