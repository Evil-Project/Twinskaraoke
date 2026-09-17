import QuartzCore
import UIKit

/// Animates the accessory's expansion, because iOS 27 does not.
///
/// Measured on an iOS 27 device. Two facts, from the frame-by-frame probe:
///
/// 1. **The expansion is never animated.** Left to settle — minimize, wait two
///    seconds, then scroll up — the accessory's presentation frame goes from
///    inline to expanded in one step, ~70ms after the model frame changed. No
///    ramp, no intermediate values. This holds for every policy-flip strategy,
///    so *who* performs the flip was never the variable.
/// 2. **A reveal asked for during the minimize is held.** The presentation
///    frame stays at the minimized geometry until ~995ms after the minimize
///    began, then jumps to full width, then ~100ms later to the expanded
///    height. That is the "lag then two pops". Notably the layers carry **no
///    `CAAnimation`s at all** while this happens: `animationKeys()` is empty on
///    the tab bar, the accessory container and its host for the whole window,
///    yet `presentation()` disagrees with the model for hundreds of
///    milliseconds. Whatever drives those values is not reachable as a local
///    animation, which is why removing animations cannot fix this on its own.
///
/// So this captures where the accessory actually *is* on screen, performs the
/// flip, and animates the affected layers from there to wherever UIKit has
/// decided they belong — supplying the transition iOS 27 omits, and overriding
/// the stale presentation with a real animation on the layer. The removal step
/// below is kept for the case where a conflicting animation does exist; on the
/// measured device it finds nothing to remove.
///
/// Nothing private is called: the views are found by class name and only
/// `layer` is touched, which every `UIView` has. Frames are read, never
/// assigned — UIKit stays the only thing that lays the accessory out.
enum TabRevealTransition {
    /// Matched to the ~200ms ramp measured on UIKit's own scroll-driven reveal,
    /// which is the transition this one stands in for. 0.45s read as sluggish on
    /// the device; it also held `.never` twice as long as it needed to.
    static let duration: CFTimeInterval = 0.22

    /// A reveal asked for while the minimize is still resolving gets overtaken:
    /// whatever drives those presentation values finishes on its own schedule
    /// (~1s from the minimize) and snaps the accessory to the model frame,
    /// which is the residual "jumps above the tab bar" flash. This is how long
    /// the correction that absorbs that snap takes.
    static let correctionDuration: CFTimeInterval = 0.12

    /// How long after a reveal to keep watching for that snap. The measured
    /// worst case is ~1.1s from the minimize, so a reveal asked for at the very
    /// start of one has about this long left to run.
    static let correctionWindow: CFTimeInterval = 1.2

    static func animatingExpansion(in controller: UITabBarController, _ flip: () -> Void) {
        let layers = accessoryLayers(in: controller)
        var before: [ObjectIdentifier: CGRect] = [:]
        for layer in layers {
            before[ObjectIdentifier(layer)] = layer.presentation()?.frame ?? layer.frame
        }

        flip()

        // UIKit applies the new geometry in its own layout pass. Forcing one
        // from here would run a whole tab-controller layout from inside the
        // scroll callback that asked for the reveal; waiting a turn reaches the
        // same frames without reentering UIKit mid-update.
        Task { @MainActor in
            for layer in layers {
                guard let from = before[ObjectIdentifier(layer)] else { continue }
                let to = layer.frame
                guard !from.equalTo(to) else { continue }
                clearGeometryAnimations(on: layer)
                add(from: from, to: to, on: layer, duration: duration)
            }
            TabRevealSettler.shared.watch(layers)
        }
    }

    /// Animates a layer from wherever it is now to its model frame. Used by the
    /// settler when something else has moved the presentation out from under
    /// the reveal.
    static func correct(_ layer: CALayer) {
        guard let from = layer.presentation()?.frame else { return }
        let to = layer.frame
        guard !from.equalTo(to) else { return }
        add(from: from, to: to, on: layer, duration: correctionDuration)
    }

    // MARK: - Animation

    static let positionKey = "nk.reveal.position"

    private static func add(from: CGRect, to: CGRect, on layer: CALayer, duration: CFTimeInterval) {
        let anchor = layer.anchorPoint
        let origin = CGPoint(
            x: from.minX + from.width * anchor.x,
            y: from.minY + from.height * anchor.y
        )

        let position = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        position.keyPath = "position"
        position.fromValue = NSValue(cgPoint: origin)
        position.toValue = NSValue(cgPoint: layer.position)

        let bounds = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        bounds.keyPath = "bounds.size"
        bounds.fromValue = NSValue(cgSize: from.size)
        bounds.toValue = NSValue(cgSize: layer.bounds.size)

        // Capped rather than taken from `settlingDuration`: the reveal holds
        // `.never` for as long as it runs, and a spring that keeps settling for
        // a second and a half is a second and a half of tab bar that cannot
        // minimize.
        position.duration = min(position.settlingDuration, duration)
        bounds.duration = min(bounds.settlingDuration, duration)

        layer.add(position, forKey: positionKey)
        layer.add(bounds, forKey: "nk.reveal.bounds")
    }

    /// Removes only what would fight this: a stale animation on the same
    /// properties. Anything else UIKit has running on the layer is left alone.
    private static func clearGeometryAnimations(on layer: CALayer) {
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key),
                  touchesGeometry(animation) else { continue }
            layer.removeAnimation(forKey: key)
        }
    }

    private static func touchesGeometry(_ animation: CAAnimation) -> Bool {
        if let group = animation as? CAAnimationGroup {
            return group.animations?.contains(where: touchesGeometry) ?? false
        }
        guard let keyPath = (animation as? CAPropertyAnimation)?.keyPath else { return false }
        return keyPath.hasPrefix("position") || keyPath.hasPrefix("bounds")
    }

    // MARK: - Hierarchy

    /// The accessory container and everything under it. The container is what
    /// carries the glass and the move; its descendants change width with it and
    /// carry stale animations of their own.
    static func accessoryLayers(in controller: UITabBarController) -> [CALayer] {
        guard let container = accessoryContainer(in: controller.view) else { return [] }
        var layers: [CALayer] = []
        var stack = [container]
        while let view = stack.popLast() {
            layers.append(view.layer)
            stack.append(contentsOf: view.subviews)
        }
        return layers
    }

    /// Breadth-first, so this is the outermost accessory view — the container
    /// that actually moves — rather than whichever descendant a depth-first
    /// walk happened to reach first.
    private static func accessoryContainer(in root: UIView) -> UIView? {
        var queue = [root]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            if String(describing: type(of: view)).range(of: "accessory", options: .caseInsensitive) != nil {
                return view
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

/// Keeps the accessory where the reveal put it.
///
/// A reveal asked for during a minimize gets overtaken. Whatever drives those
/// presentation values — not a `CAAnimation`, the layers carry none — resolves
/// on its own schedule, about a second after the minimize began, and snaps the
/// accessory to whatever the model frame says. If the reveal's own animation
/// has already finished by then, that snap is visible as the accessory jumping
/// into place above the tab bar.
///
/// So the reveal is not finished when its animation ends. This watches for that
/// snap and answers it with a short animation from wherever the layer actually
/// is, turning a jump into a glide. It stops as soon as the window in which a
/// snap can still arrive has passed, and it never touches a layer whose reveal
/// animation is still running.
@MainActor
final class TabRevealSettler: NSObject {
    static let shared = TabRevealSettler()

    private var link: CADisplayLink?
    private var layers: [CALayer] = []
    private var deadline: CFTimeInterval = 0

    func watch(_ layers: [CALayer]) {
        self.layers = layers
        deadline = CACurrentMediaTime() + TabRevealTransition.correctionWindow
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        layers = []
    }

    @objc private func tick() {
        guard CACurrentMediaTime() < deadline else {
            stop()
            return
        }
        for layer in layers {
            // Ours is still running; it is not a snap to answer.
            guard layer.animation(forKey: TabRevealTransition.positionKey) == nil else { continue }
            guard let presented = layer.presentation()?.frame else { continue }
            let model = layer.frame
            // A pixel of drift is the tail of a settling spring, not a jump.
            let drift = abs(presented.minX - model.minX)
                + abs(presented.minY - model.minY)
                + abs(presented.width - model.width)
                + abs(presented.height - model.height)
            guard drift > 1 else { continue }
            TabRevealTransition.correct(layer)
        }
    }
}
