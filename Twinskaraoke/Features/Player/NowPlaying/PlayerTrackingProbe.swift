#if DEBUG
import SwiftUI
import UIKit

enum PlayerClosingTestArtwork {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-UITestPlayerClosingArtwork")
    static let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        UIColor.systemIndigo.setFill()
        context.fill(CGRect(x: 150, y: 0, width: 150, height: 300))
    }
}

/// Simulates an ancestor accessory press winning before upward movement.
/// Installed only by the dedicated regression test, never in normal launches.
struct PlayerGestureCompetitionProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> CompetitionView { CompetitionView() }
    func updateUIView(_ uiView: CompetitionView, context: Context) {}

    final class CompetitionView: UIView, UIGestureRecognizerDelegate {
        private lazy var press = UILongPressGestureRecognizer(target: self, action: #selector(recognized))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            press.view?.removeGestureRecognizer(press)
            guard let window else { return }
            isUserInteractionEnabled = false
            press.minimumPressDuration = 0.01
            press.allowableMovement = 1000
            press.cancelsTouchesInView = false
            press.delegate = self
            window.addGestureRecognizer(press)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window else { return false }
            return NowPlayingSnapshotState.shared.hasCurrentSong
                && !NowPlayingPresentation.shared.isExpanded
                && touch.location(in: window).y > window.bounds.height * 0.75
        }

        @objc private func recognized() {}
    }
}

struct PlayerLandingArtworkProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ uiView: Marker, context: Context) {}

    final class Marker: UIView {
        static weak var current: Marker?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if window != nil { Self.current = self }
        }
    }
}

/// UI-test-only measurement of the rendered player while the finger is down.
/// Sampling on the display link avoids mistaking an endpoint update for an
/// interactive transition. This view is never installed in normal launches.
struct PlayerTrackingProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private var displayLink: CADisplayLink?
        private var openingOffsets: [CGFloat] = []
        private var closingOffsets: [CGFloat] = []
        private var landingSamples = 0
        private var landingOvershoot: CGFloat = 0

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "PlayerTrackingProbe"
            accessibilityLabel = "Player tracking measurements"
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate()
            displayLink = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sample))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func sample() {
            let presentation = NowPlayingPresentation.shared
            guard presentation.isDragging || presentation.isSettlingArtwork, let window else { return }
            let y = (layer.presentation() ?? layer)
                .convert(.zero, to: window.layer.presentation() ?? window.layer).y
            if presentation.isSettlingArtwork {
                if let marker = PlayerLandingArtworkProbe.Marker.current, marker.window === window,
                   let thumbnail = presentation.barArtworkFrame {
                    let rendered = marker.layer.presentation() ?? marker.layer
                    let center = rendered.convert(CGPoint(x: rendered.bounds.midX, y: rendered.bounds.midY),
                                                  to: window.layer.presentation() ?? window.layer)
                    landingSamples += 1
                    landingOvershoot = max(landingOvershoot, center.y - thumbnail.midY)
                }
            } else if presentation.isExpanded {
                closingOffsets.append(y)
            } else {
                openingOffsets.append(y)
            }
            let openingTravel = (openingOffsets.max() ?? 0) - (openingOffsets.min() ?? 0)
            let closingTravel = (closingOffsets.max() ?? 0) - (closingOffsets.min() ?? 0)
            // Distinct intermediate positions reject an immediate endpoint jump.
            let openingSteps = Set(openingOffsets.filter { $0 > 30 && $0 < window.bounds.height - 30 }.map { Int($0 / 10) }).count
            let closingSteps = Set(closingOffsets.filter { $0 > 30 && $0 < window.bounds.height - 30 }.map { Int($0 / 10) }).count
            accessibilityValue = "\(Int(openingTravel)),\(Int(closingTravel)),\(openingSteps),\(closingSteps),\(landingSamples),\(Int(landingOvershoot))"
        }
    }
}
#endif
