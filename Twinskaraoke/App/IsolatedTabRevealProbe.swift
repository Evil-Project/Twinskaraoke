import SwiftUI

/// A tab bar with an accessory and nothing of this app's around it.
///
/// Everything measured so far was measured inside the real shell, so every
/// result has been about "iOS 27 plus this app" and none of it can say which
/// half is responsible. This screen is the control: a `TabView`, three tabs, a
/// `NavigationStack`, a plain `ScrollView`, and a `tabViewBottomAccessory` whose
/// content is two `Image`s and a `Text`. It has no `MiniPlayerBar`, no
/// window-level gesture, no touch-region markers, no Shimeji, no player overlay
/// and no Search-prominence installer — so if the reveal glitches here too, none
/// of those can be the cause, and if it does not, one of them is.
///
/// It uses the same `TabRevealStrategy` the developer menu selects, so the
/// comparison is like for like: pick a strategy, watch it here, then watch the
/// same strategy in the app.
///
/// This existed before as a `#if DEBUG` screen behind a launch argument, which
/// is why it has only ever run on the simulator: device builds of this project
/// are Release, so it was compiled out of every build that reached an iOS 27
/// device. It is Release-reachable now, from Developer.
struct IsolatedTabRevealProbe: View {
    var onClose: (() -> Void)?

    @State private var reveal = TabScrollRevealState()
    @State private var offset = 0
    private var strategy: TabRevealStrategy {
        // The UI test pins the shipping per-OS strategy. Nothing read this
        // argument before, so the probe fell through to whatever Developer had
        // stored — and a diagnostic strategy left selected there silently
        // changes what the test measures.
        if ProcessInfo.processInfo.arguments.contains("-UITestThresholdTabReveal") {
            return TabRevealStrategy.automatic.resolved
        }
        return TabRevealStrategy.current.resolved
    }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<200, id: \.self) { row in
                                Text("Row \(row)")
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            }
                        }
                    }
                    .modifier(IsolatedRevealScrolling(isEnabled: strategy.usesThreshold))
                    .accessibilityIdentifier("NativeReveal.Scroll")
                    .onScrollGeometryChange(for: Int.self) {
                        Int($0.contentOffset.y + $0.contentInsets.top)
                    } action: { _, value in offset = value }
                    .navigationTitle("Isolated reveal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if let onClose {
                                Button("Close", action: onClose)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Text("\(offset)")
                                .monospacedDigit()
                                .accessibilityIdentifier("NativeReveal.Offset")
                                .accessibilityValue(
                                    strategy.usesThreshold && reveal.isRevealed ? "revealing" : "native"
                                )
                        }
                    }
                }
            }
            Tab("Library", systemImage: "music.note.list") { Text("Library") }
            Tab("Search", systemImage: "magnifyingglass", role: .search) { Text("Search") }
        }
        .modifier(ThresholdTabBehavior(
            state: strategy.usesThreshold ? reveal : nil,
            strategy: strategy
        ))
        .tabViewBottomAccessory { IsolatedRevealAccessory() }
    }
}

/// The threshold needs the shared scroll observation; without it there is no
/// upward distance to measure. Off, the scroll view is untouched and only
/// UIKit's own reveal can fire.
private struct IsolatedRevealScrolling: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled { content.smoothScrolling() } else { content }
    }
}

/// Deliberately plain: it changes size with placement, the way the real bar
/// does, and does nothing else. No geometry reporting, no touch regions, no
/// marquee, no observation of app state.
private struct IsolatedRevealAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack {
            Image(systemName: "music.note")
                .frame(width: isInline ? 30 : 40, height: isInline ? 30 : 40)
                .background(.blue, in: RoundedRectangle(cornerRadius: 6))
            Text(isInline ? "inline" : "expanded")
                .accessibilityIdentifier("NativeReveal.Placement")
            Spacer()
            Image(systemName: "play.fill")
            if !isInline { Image(systemName: "forward.end.fill") }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: isInline ? 48 : 58)
        .clipped()
    }
}
