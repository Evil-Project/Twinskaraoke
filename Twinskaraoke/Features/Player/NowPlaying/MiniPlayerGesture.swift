import SwiftUI
import UIKit

/// Temporary device tracing in Debug and Release for the affected device build.
/// No song, account, or other content is recorded.
/// Keep a version stamp so a device report identifies the installed code path.
enum PlayerGestureTrace {
    static func record(_ message: @autoclosure () -> String) {
        print("[PlayerGesture D2] \(message())")
    }
}

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
            PlayerGestureTrace.record("host=\(ObjectIdentifier(self)) window=\(String(describing: window.map(ObjectIdentifier.init))) OS=\(UIDevice.current.systemVersion)")
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
                PlayerGestureTrace.record("host=\(ObjectIdentifier(self)) reject: no window")
                return false
            }
            let point = touch.location(in: window)
            let allRegions = MiniPlayerTouchRegion.Marker.live.allObjects.filter { $0.window === window }
            let regions = allRegions.filter(\.isVisible)
            let acceptsTap = !regions.contains { $0.isTransport && $0.convert($0.bounds, to: window).contains(point) }
            let inBar = regions.contains { !$0.isTransport && $0.convert($0.bounds, to: window).contains(point) }
            let modal = Self.hasPresentedController(window.rootViewController)
            let eligible = recognizer.canBegin()
            if eligible && !modal { recognizer.acceptsTap = acceptsTap }
            let accepted = eligible && !modal && inBar
            PlayerGestureTrace.record("host=\(ObjectIdentifier(self)) receive=\(accepted) point=\(point) eligible=\(eligible) modal=\(modal) inBar=\(inBar) control=\(!acceptsTap) expanded=\(presentation.isExpanded) owner=\(String(describing: presentation.dragSource)) animating=\(presentation.isAnimatingTransition) progress=\(presentation.progress)")
            PlayerGestureTrace.record("regions=\(allRegions.map { "\($0.isTransport ? "controls" : "bar") visible=\($0.isVisible) frame=\($0.convert($0.bounds, to: window))" }.joined(separator: "; "))")
            return accepted
        }

        private static func hasPresentedController(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            return controller.presentedViewController != nil || controller.children.contains { hasPresentedController($0) }
        }

        @objc private func handle() {
            let contact = recognizer.contact
            switch recognizer.state {
            case .began, .changed:
                withTransaction(Transaction(animation: nil)) {
                    presentation.drag(to: PlayerDismissMetrics.openingProgress(
                        translation: contact.translation, height: contact.height), from: .miniPlayer)
                }
                if recognizer.state == .began {
                    PlayerGestureTrace.record("tracking began translation=\(contact.translation) progress=\(presentation.progress) owner=\(String(describing: presentation.dragSource))")
                }
            case .ended:
                if contact.isDragging {
                    let opens = PlayerDismissMetrics.shouldOpen(translation: contact.translation,
                        predictedTranslation: contact.projectedTranslation, height: contact.height)
                    presentation.endDrag(dismissing: !opens, from: .miniPlayer)
                    PlayerGestureTrace.record("release open=\(opens) translation=\(contact.translation) projected=\(contact.projectedTranslation) expanded=\(presentation.isExpanded) animating=\(presentation.isAnimatingTransition) token=\(presentation.animationToken)")
                } else {
                    PlayerGestureTrace.record("tap expand")
                    presentation.expand()
                }
            case .cancelled, .failed:
                PlayerGestureTrace.record("action cancelled/failed state=\(recognizer.state.rawValue) translation=\(contact.translation)")
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
        private var moveEvents = 0

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
                PlayerGestureTrace.record("raw begin rejected eligible=\(canBegin()) alreadyTracking=\(trackedTouch != nil) touchCount=\(touches.count)")
                state = state == .possible ? .failed : .cancelled
                return
            }
            trackedTouch = touch
            contactWindow = window
            contact.begin(at: touch.location(in: window), time: touch.timestamp, height: window.bounds.height)
            PlayerGestureTrace.record("raw begin height=\(window.bounds.height) acceptsTap=\(acceptsTap)")
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            guard let touch = trackedTouch, touches.contains(touch), let window = contactWindow else { return }
            let wasDragging = contact.isDragging
            moveEvents += 1
            switch contact.move(to: touch.location(in: window), time: touch.timestamp) {
            case .waiting: break
            case .dragging: state = wasDragging ? .changed : .began
            case .rejected:
                PlayerGestureTrace.record("raw direction rejected translation=\(contact.translation) moves=\(moveEvents)")
                state = .failed
            }
            if moveEvents == 1 || moveEvents.isMultiple(of: 10) {
                PlayerGestureTrace.record("raw move count=\(moveEvents) state=\(state.rawValue) translation=\(contact.translation) modelProgress=\(NowPlayingPresentation.shared.progress)")
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
            PlayerGestureTrace.record("raw end recognized=\(recognized) drag=\(contact.isDragging) moves=\(moveEvents) translation=\(contact.translation) projected=\(contact.projectedTranslation)")
            state = recognized && (contact.isDragging || acceptsTap) ? .ended : .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            PlayerGestureTrace.record("raw cancelled moves=\(moveEvents) translation=\(contact.translation)")
            state = .cancelled
        }

        override func reset() {
            PlayerGestureTrace.record("reset state=\(state.rawValue) tracked=\(trackedTouch != nil) moves=\(moveEvents)")
            super.reset()
            trackedTouch = nil
            contactWindow = nil
            contact = MiniPlayerContact()
            moveEvents = 0
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
