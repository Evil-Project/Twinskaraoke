import SwiftUI

extension View {
    /// Pull to refresh, with the one haptic every refresh in the app plays: a
    /// tick as the refresh begins.
    ///
    /// Each screen wrote this out for itself, and they had drifted apart: most
    /// ticked, three also played a success when the load came back, and two
    /// were silent. Nothing marks the end; the content arriving is the result.
    /// Radio is the exception: its refresh shares its Retry button's outcome
    /// haptic, because a failed one leaves an error on screen.
    func refreshableWithTick(_ action: @escaping @MainActor () async -> Void) -> some View {
        refreshable {
            AppHaptic.selection.play()
            await action()
        }
    }
}
