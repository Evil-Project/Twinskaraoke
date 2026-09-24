import SwiftUI
import UIKit

/// A single recognizer owns the complete contact. A pan can never fall through
/// to a second tap recognizer when the system accessory changes its layout.
struct MiniPlayerGesture: UIViewRepresentable {
    func makeUIView(context: Context) -> Host { Host() }
    func updateUIView(_ uiView: Host, context: Context) {}

    final class Host: UIView, UIGestureRecognizerDelegate {
        private lazy var recognizer = Recognizer(target: self, action: #selector(handle))
        private let presentation = NowPlayingPresentation.shared

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            guard let window else {
                presentation.cancelDrag(from: .miniPlayer)
                return
            }
            isUserInteractionEnabled = false
            recognizer.delegate = self
            recognizer.canBegin = { [weak self] in
                guard let self else { return false }
                return presentation.canBeginMiniPlayerContact
            }
            window.addGestureRecognizer(recognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window else {
                return false
            }
            let point = touch.location(in: window)
            let allRegions = MiniPlayerTouchRegion.Marker.live.allObjects.filter { $0.window === window }
            let regions = allRegions.filter(\.isVisible)
            let acceptsTap = !regions.contains { $0.isTransport && $0.convert($0.bounds, to: window).contains(point) }
            let inBar = regions.contains { !$0.isTransport && $0.convert($0.bounds, to: window).contains(point) }
            let modal = Self.hasCoveringPresentation(window.rootViewController)
            let eligible = recognizer.canBegin()
            if eligible && !modal { recognizer.acceptsTap = acceptsTap }
            let accepted = eligible && !modal && inBar
            return accepted
        }

        /// Whether something is presented over the bar.
        ///
        /// An active search is a presentation too — the search tab presents its
        /// `UISearchController`, and it stays presented after switching to
        /// another tab — but it covers only its own tab's content. The accessory
        /// stays on screen above it, so treating it as a modal left the mini
        /// player dead on every tab from the first search until that search was
        /// cancelled. Anything the search presents in turn (a sheet from a
        /// result's menu) still counts.
        ///
        /// A child reports its ancestors' presentations as its own, so only the
        /// actual presenter answers for each one; that is also what stops the
        /// walk from re-entering a search controller through its own results.
        private static func hasCoveringPresentation(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            if let presented = controller.presentedViewController,
               presented.presentingViewController === controller
            {
                if !(presented is UISearchController) || hasCoveringPresentation(presented) {
                    return true
                }
            }
            return controller.children.contains { hasCoveringPresentation($0) }
        }

        @objc private func handle() {
            let contact = recognizer.contact
            switch recognizer.state {
            case .began, .changed:
                withTransaction(Transaction(animation: nil)) {
                    presentation.drag(to: PlayerDismissMetrics.openingProgress(
                        translation: contact.translation, height: contact.height), from: .miniPlayer)
                }
            case .ended:
                if contact.isDragging {
                    let opens = PlayerDismissMetrics.shouldOpen(translation: contact.translation,
                        predictedTranslation: contact.projectedTranslation, height: contact.height)
                    presentation.endDrag(dismissing: !opens, from: .miniPlayer)
                } else {
                    presentation.expand()
                }
            case .cancelled, .failed:
                presentation.cancelDrag(from: .miniPlayer)
            default:
                break
            }
        }
    }

    final class Recognizer: UIGestureRecognizer {
        var canBegin: () -> Bool = { false }
        var acceptsTap = true
        private(set) var contact = MiniPlayerContact()
        private weak var contactWindow: UIWindow?
        private var trackedTouch: UITouch?

        // The delegate admits only mini-player contacts, excluding modal
        // presentations. Native accessory gestures must not prevent
        // this window-owned stream, even when their hosting views are replaced.
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            guard canBegin(), trackedTouch == nil, touches.count == 1,
                  let touch = touches.first, let window = (view as? UIWindow) ?? view?.window else {
                state = state == .possible ? .failed : .cancelled
                return
            }
            trackedTouch = touch
            contactWindow = window
            contact.begin(at: touch.location(in: window), time: touch.timestamp, height: window.bounds.height)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            guard let touch = trackedTouch, touches.contains(touch), let window = contactWindow else { return }
            let wasDragging = contact.isDragging
            switch contact.move(to: touch.location(in: window), time: touch.timestamp) {
            case .waiting: break
            case .dragging: state = wasDragging ? .changed : .began
            case .rejected:
                state = .failed
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesEnded(touches, with: event)
            guard let touch = trackedTouch, touches.contains(touch), let window = contactWindow else {
                state = .failed
                return
            }
            // A long stationary hold contributes zero release velocity.
            let recognized = contact.finish(at: touch.location(in: window), time: touch.timestamp)
            state = recognized && (contact.isDragging || acceptsTap) ? .ended : .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            state = .cancelled
        }

        override func reset() {
            super.reset()
            trackedTouch = nil
            contactWindow = nil
            contact = MiniPlayerContact()
        }
    }
}

/// Non-interactive markers measure actual UIKit bounds in the owning window.
/// Multiple native accessory placements can coexist; only visible markers count.
struct MiniPlayerTouchRegion: UIViewRepresentable {
    var isTransport = false
    func makeUIView(context: Context) -> Marker {
        let marker = Marker()
        marker.isTransport = isTransport
        marker.isUserInteractionEnabled = false
        Marker.live.add(marker)
        return marker
    }
    func updateUIView(_ uiView: Marker, context: Context) {}

    final class Marker: UIView {
        static let live = NSHashTable<Marker>.weakObjects()
        var isTransport = false
        var isVisible: Bool {
            var ancestor: UIView? = self
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                ancestor = view.superview
            }
            return !bounds.isEmpty
        }
    }
}

/// Window coordinates and the travel height are frozen at touch-down. Native
/// accessory resizing must not turn a few points of finger movement into a
/// screenful of relative translation.
struct MiniPlayerContact {
    enum Movement { case waiting, dragging, rejected }
    private var origin = CGPoint.zero
    private var previousPoint = CGPoint.zero
    private var previousTime: TimeInterval = 0
    private var lastMovementTime: TimeInterval = 0
    private var velocity: CGFloat = 0
    private(set) var height: CGFloat = 1
    private(set) var translation: CGFloat = 0
    private(set) var isDragging = false

    var projectedTranslation: CGFloat { translation + velocity * 0.25 }

    mutating func begin(at point: CGPoint, time: TimeInterval, height: CGFloat) {
        self = MiniPlayerContact()
        origin = point
        previousPoint = point
        previousTime = time
        lastMovementTime = time
        self.height = max(1, height)
    }

    mutating func move(to point: CGPoint, time: TimeInterval) -> Movement {
        update(point: point, time: time)
        if !isDragging {
            let horizontal = point.x - origin.x
            guard max(abs(horizontal), abs(translation)) >= 4 else { return .waiting }
            guard translation < 0, abs(translation) > abs(horizontal) else {
                // Allow small initial sideways jitter to resolve into an
                // upward gesture before yielding to a horizontal gesture.
                return max(abs(horizontal), abs(translation)) < 12 ? .waiting : .rejected
            }
            isDragging = true
        }
        return .dragging
    }

    @discardableResult
    mutating func finish(at point: CGPoint, time: TimeInterval) -> Bool {
        // Preserve the last movement's velocity for a quick lift, but discard
        // it after a hold; touch-up may have the same position as the last move.
        update(point: point, time: time)
        // A coalesced/missing move event must not turn a moved contact into a tap.
        return isDragging || max(abs(point.x - origin.x), abs(translation)) < 4
    }

    private mutating func update(point: CGPoint, time: TimeInterval) {
        let elapsed = time - previousTime
        let movement = point.y - previousPoint.y
        if elapsed > 0, movement != 0 {
            velocity = movement / elapsed
            lastMovementTime = time
        } else if time - lastMovementTime > 0.1 {
            velocity = 0
        }
        translation = point.y - origin.y
        previousPoint = point
        previousTime = time
    }
}
