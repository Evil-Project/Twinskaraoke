import QuartzCore
import UIKit

/// Records what the tab bar and the accessory actually do, frame by frame,
/// across one reveal or minimization.
///
/// Placement assertions cannot tell "expanded without animating" from
/// "expanded smoothly" — both end in the same place. The discriminator is the
/// presentation layer: while Core Animation is interpolating, a layer's
/// `presentation()` frame differs from its model frame, and the difference
/// closes over the transition. A reveal that jumps produces one line where
/// model and presentation already agree.
///
/// Off unless `nk.tabRevealDiagnostics` is set, and it writes through
/// `DebugLogger`, so a Release device build carries it.
@MainActor
final class TabRevealProbe: NSObject {
    static let shared = TabRevealProbe()

    private var link: CADisplayLink?
    private weak var controller: UITabBarController?
    private var startedAt: CFTimeInterval = 0
    private var label = ""
    private var duration: CFTimeInterval = 0.9
    private var lastAnimations = ""

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "nk.tabRevealDiagnostics")
    }

    static let storageKey = "nk.tabRevealDiagnostics"

    /// `controller` is optional so SwiftUI call sites do not have to find one.
    func record(_ label: String, controller: UITabBarController? = nil) {
        guard Self.isEnabled else { return }
        guard let controller = controller ?? Self.resolveController() else {
            DebugLogger.log("reveal[\(label)] no tab bar controller", category: .ui)
            return
        }
        stop()
        self.controller = controller
        self.label = label
        lastAnimations = ""
        startedAt = CACurrentMediaTime()
        DebugLogger.log(
            "reveal[\(label)] begin mode=\(Self.describe(controller.tabBarMinimizeBehavior)) "
                + "strategy=\(TabRevealStrategy.current.rawValue) "
                + "tracked=\(Self.tracked(in: controller).map { $0.0 }.joined(separator: ","))",
            category: .ui
        )
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Standalone events that belong on the same timeline — an accessory
    /// placement flip, say — so their ordering against the frames is readable.
    ///
    /// A placement flip is also the only trace of a reveal the app did not ask
    /// for: UIKit's own long-distance one. Recording when nothing else is
    /// already recording puts those on the same footing as ours without cutting
    /// an in-flight window short.
    static func note(_ message: String) {
        guard isEnabled else { return }
        DebugLogger.log("reveal[note] \(message)", category: .ui)
        shared.recordIfIdle("native-" + message.replacingOccurrences(of: " ", with: ""))
    }

    func recordIfIdle(_ label: String) {
        guard link == nil else { return }
        record(label)
    }

    func stop() {
        link?.invalidate()
        link = nil
        controller = nil
    }

    @objc private func tick() {
        guard let controller else {
            stop()
            return
        }
        let elapsed = (CACurrentMediaTime() - startedAt) * 1000
        var parts: [String] = []
        var animations: [String] = []
        for (name, view) in Self.tracked(in: controller) {
            let model = view.layer.frame
            let presented = view.layer.presentation()?.frame
            let animating = presented.map { !$0.equalTo(model) } ?? false
            parts.append(
                "\(name) model=\(Self.describe(model)) "
                    + "pres=\(presented.map(Self.describe) ?? "nil")\(animating ? " *" : "")"
            )
            animations.append("\(name)[\(Self.describe(view.layer))]")
        }
        // Whose animation is holding the frame, and how long it runs, is the
        // thing the frames alone could only be read as. Logged on change only.
        let summary = animations.joined(separator: " ")
        if summary != lastAnimations {
            lastAnimations = summary
            DebugLogger.log("reveal[\(label)] t=\(Int(elapsed))ms anim \(summary)", category: .ui)
        }
        DebugLogger.log(
            "reveal[\(label)] t=\(Int(elapsed))ms \(parts.joined(separator: " | "))",
            category: .ui
        )
        if elapsed >= duration * 1000 { stop() }
    }

    // MARK: - Hierarchy

    /// The tab bar plus every accessory-hosting view under the controller.
    /// Matching on the class name keeps this out of private API: nothing is
    /// called on those views beyond `layer`, which every `UIView` has.
    private static func tracked(in controller: UITabBarController) -> [(String, UIView)] {
        var result: [(String, UIView)] = [("bar", controller.tabBar)]
        var index = 0
        var stack: [UIView] = [controller.view]
        while let view = stack.popLast() {
            let name = String(describing: type(of: view))
            if name.range(of: "accessory", options: .caseInsensitive) != nil {
                result.append(("acc\(index)/\(name)", view))
                index += 1
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    private static func resolveController() -> UITabBarController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        return TabRevealBridgeView.tabBarController(in: window?.rootViewController)
    }

    /// Every running animation on the layer, with the property it drives and
    /// how long it has left.
    private static func describe(_ layer: CALayer) -> String {
        let keys = layer.animationKeys() ?? []
        guard !keys.isEmpty else { return "-" }
        return keys.map { key in
            guard let animation = layer.animation(forKey: key) else { return key }
            let property = (animation as? CAPropertyAnimation)?.keyPath
                ?? ((animation as? CAAnimationGroup).map { group in
                    (group.animations ?? [])
                        .compactMap { ($0 as? CAPropertyAnimation)?.keyPath }
                        .joined(separator: "+")
                } ?? "?")
            return "\(key):\(property):\(Int(animation.duration * 1000))ms"
        }.joined(separator: ",")
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height)))"
    }

    private static func describe(_ behavior: UITabBarController.MinimizeBehavior) -> String {
        switch behavior {
        case .never: "never"
        case .onScrollDown: "onScrollDown"
        case .onScrollUp: "onScrollUp"
        case .automatic: "automatic"
        @unknown default: "unknown"
        }
    }
}
