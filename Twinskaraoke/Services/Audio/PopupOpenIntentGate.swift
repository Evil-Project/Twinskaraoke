import LNPopupUI
import SwiftUI

#if canImport(UIKit)
    import UIKit

    @MainActor
    final class PopupOpenIntentGate: NSObject, UIGestureRecognizerDelegate {
        static let shared = PopupOpenIntentGate()

        private static let touchRecognizerName = "Twinskaraoke.IntentionalMiniPlayerOpen"
        private static let defaultTrailingControlHitWidth: CGFloat = 132
        // Radio mode shows a single 44pt play/stop button, so its control zone
        // is narrower than the two-button default.
        private static let radioTrailingControlHitWidth: CGFloat = 96
        private static let tapMovementTolerance: CGFloat = 12
        private static let visibleBarHitHeight: CGFloat = 116
        private static let openIntentWindow: TimeInterval = 0.45
        private static let openDragReleaseWindow: TimeInterval = 1.2
        private var touchStartLocation: CGPoint?
        private var isOpenDragActive = false
        private var openIntentExpiresAt = Date.distantPast
        private var suppressOpenExpiresAt = Date.distantPast

        func consumeIntent() -> Bool {
            guard Date() > suppressOpenExpiresAt else {
                isOpenDragActive = false
                openIntentExpiresAt = .distantPast
                return false
            }
            suppressOpenExpiresAt = .distantPast
            if isOpenDragActive {
                openIntentExpiresAt = Date().addingTimeInterval(Self.openIntentWindow)
                return true
            }
            guard Date() <= openIntentExpiresAt else {
                openIntentExpiresAt = .distantPast
                return false
            }
            openIntentExpiresAt = .distantPast
            return true
        }

        func suppressNextOpen() {
            isOpenDragActive = false
            openIntentExpiresAt = .distantPast
            suppressOpenExpiresAt = Date().addingTimeInterval(Self.openIntentWindow)
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
                isOpenDragActive = false
                guard Date() > suppressOpenExpiresAt,
                      isVisibleMiniPlayerTouch(location, in: popupBar)
                else {
                    touchStartLocation = nil
                    openIntentExpiresAt = .distantPast
                    return
                }
                touchStartLocation = location
                // A tap on the trailing playback controls must not open the
                // popup, but an upward drag starting on them is still an
                // intentional open — so only the tap intent is withheld here;
                // .changed can still arm the drag intent.
                openIntentExpiresAt = isTrailingControlTouch(location, in: popupBar)
                    ? .distantPast
                    : Date().addingTimeInterval(Self.openIntentWindow)
            case .changed:
                guard let touchStartLocation else {
                    openIntentExpiresAt = .distantPast
                    return
                }

                if isOpenDragActive {
                    // Once the user has committed to an open drag, keep the
                    // intent alive even if the finger wobbles near the start;
                    // LNPopup decides whether the gesture opens or closes.
                    openIntentExpiresAt = Date().addingTimeInterval(Self.openIntentWindow)
                } else if isIntentionalOpenDrag(from: touchStartLocation, to: location) {
                    isOpenDragActive = true
                    openIntentExpiresAt = Date().addingTimeInterval(Self.openIntentWindow)
                } else if distance(from: touchStartLocation, to: location) > Self.tapMovementTolerance {
                    openIntentExpiresAt = .distantPast
                }
            case .ended:
                touchStartLocation = nil
                if isOpenDragActive {
                    isOpenDragActive = false
                    openIntentExpiresAt = Date().addingTimeInterval(Self.openDragReleaseWindow)
                }
            case .cancelled, .failed:
                touchStartLocation = nil
                if isOpenDragActive {
                    // LNPopup's transition takes over the touch and cancels
                    // this recognizer mid-drag; that is still an intentional
                    // open, so grant the same release window as .ended.
                    isOpenDragActive = false
                    openIntentExpiresAt = Date().addingTimeInterval(Self.openDragReleaseWindow)
                } else {
                    openIntentExpiresAt = .distantPast
                }
            default:
                break
            }
        }

        private func isVisibleMiniPlayerTouch(_ location: CGPoint, in popupBar: LNPopupBar) -> Bool {
            let bounds = popupBar.bounds
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                return false
            }

            let visibleHeight = min(bounds.height, Self.visibleBarHitHeight)
            return location.x >= bounds.minX
                && location.x <= bounds.maxX
                && location.y >= bounds.minY
                && location.y <= bounds.minY + visibleHeight
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

        private func isIntentionalOpenDrag(from start: CGPoint, to current: CGPoint) -> Bool {
            let deltaX = current.x - start.x
            let deltaY = current.y - start.y
            guard deltaY < -Self.tapMovementTolerance else { return false }
            return abs(deltaY) >= abs(deltaX) * 0.75
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif
