import Observation
import SwiftUI
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
