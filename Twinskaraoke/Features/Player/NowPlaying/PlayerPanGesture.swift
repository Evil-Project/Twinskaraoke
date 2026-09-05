import SwiftUI
import UIKit

/// UIKit reports cancellation separately from finger-up. SwiftUI gesture-state
/// resets can also occur when the accessory host updates during a drag.
struct PlayerPanGesture: UIGestureRecognizerRepresentable {
    let canBegin: () -> Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(canBegin: canBegin)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view?.window).y
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            // Project a quarter-second of release velocity, symmetrically in
            // both directions. A reversal can therefore cancel the swipe.
            let projected = translation + recognizer.velocity(in: recognizer.view?.window).y * 0.25
            onEnded(translation, projected)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: () -> Bool

        init(canBegin: @escaping () -> Bool) { self.canBegin = canBegin }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard canBegin(), let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view?.window)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}
