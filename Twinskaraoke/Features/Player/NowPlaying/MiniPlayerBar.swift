import SwiftUI

/// The mini player.
///
/// This is only the bar's *content*. It is hosted in iOS 26's
/// `tabViewBottomAccessory` slot — the one Apple Music uses — so the system
/// supplies the glass, the merge into the minimized tab bar, and the bottom
/// content inset for every screen underneath. Those three things are most of
/// what the library this replaces reached for private API to approximate, and
/// none of them are ours to get wrong any more.
///
/// The interaction is the other half of the point. Opening used to be
/// unobservable: LNPopupController owned the bar's gestures and surfaced only
/// "the popup is now open", so `PopupOpenIntentGate` had to reconstruct intent
/// from raw touches — 173 lines of hit-zone arithmetic to work out whether the
/// user had meant to tap the play button. Here the play button is a button. A
/// tap on it is a tap on it, because SwiftUI resolves child gestures before the
/// container's, and the bar's own tap never sees that touch.
struct MiniPlayerBar: View {
    /// `.inline` once the tab bar has minimized and the accessory has merged
    /// into it, `.expanded` at full size, `nil` outside a `TabView` — which is
    /// the iPad sidebar, where the bar sits in a `safeAreaBar` instead and
    /// should look like the full-size one.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private let snapshot = NowPlayingSnapshotState.shared
    private let presentation = NowPlayingPresentation.shared

    /// Matches the artwork the old bar drew: LNPopupBar sized its image as
    /// `barHeight - 18`, so 40pt at the full 58pt height and 30pt at the
    /// minimized 48pt one. Keeping the numbers means the bar does not visibly
    /// change size on the day the library comes out.
    private var artworkSize: CGFloat {
        isInline ? 30 : 40
    }

    private var isInline: Bool {
        placement == .inline
    }

    var body: some View {
        HStack(spacing: 10) {
            artwork
            titles
            Spacer(minLength: 8)
            MiniPlayerTransportControls(
                isPlaying: snapshot.isPlaying,
                isRadioMode: snapshot.isRadioMode,
                showsNext: !isInline
            )
        }
        .padding(.horizontal, 12)
        // Leading-anchored and clipped so the contents stay put and never spill
        // while the container is between its two sizes.
        //
        // This is defensive, not the cure: the shift that was visible on
        // expansion was the *container's*, measured at x=84 w=234 inline versus
        // x=21 w=360 expanded, and no content alignment can move that. See
        // `TabBarMinimizeCoordinator.expandedHold`. There is still a short
        // window where the accessory is inline-sized while its contents are
        // expanded-shaped, and this is what keeps that from being ragged.
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        // The shape change itself is deliberately not animated: the system is
        // already animating the container, and putting the contents on a
        // second, unrelated curve made the move read as two movements.
        .animation(nil, value: isInline)
        // The whole bar is one big open affordance, but only where a child has
        // not already claimed the touch. `contentShape` is what makes the gaps
        // between the artwork, the titles and the buttons tappable at all —
        // without it a tap on empty space falls straight through to the tab bar.
        .contentShape(.rect)
        .onTapGesture {
            presentation.expand()
        }
        // Flicking up opens too, the way it did before. Plain `.gesture`, so a
        // drag that starts on the play button still belongs to the button.
        .gesture(openDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MiniPlayerBar")
        .accessibilityLabel("Now Playing")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the full-screen player.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            presentation.expand()
        }
        // Shimeji rest on the bar's top edge. Reporting the frame as SwiftUI
        // lays it out replaces the half-second poll that was the only way to
        // follow a `UIView` the app did not own — which is why sprites used to
        // lag the bar whenever the tab bar minimized.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            ShimejiMiniPlayerTracker.shared.report(frame: frame)
        }
        .onDisappear {
            ShimejiMiniPlayerTracker.shared.report(frame: nil)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = snapshot.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                MusicArtworkPlaceholder(cornerRadius: AM.Radius.thumb)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: AM.Radius.thumb, style: .continuous))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            presentation.reportBarArtworkFrame(frame)
        }
        // Hidden while the flying artwork stands in for it, so the two are
        // never on screen at the same time.
        .opacity(presentation.isMorphingArtwork ? 0 : 1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            // Dropped when inline: the minimized bar is 48pt tall and shared
            // with the tab pill, and two lines of text there reads as clutter
            // rather than information.
            if !isInline, !snapshot.subtitle.isEmpty {
                Text(snapshot.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityHidden(true)
    }

    /// Upward only, and judged on where the finger ended rather than on
    /// velocity: opening is a cheap, reversible action, so it should be easy to
    /// trigger. Dismissal is the one that needs a considered predicate — see
    /// `PlayerDismissMetrics`.
    private var openDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard value.translation.height < -20 else { return }
                presentation.expand()
            }
    }

    private var accessibilityValue: String {
        snapshot.subtitle.isEmpty ? snapshot.title : "\(snapshot.title), \(snapshot.subtitle)"
    }
}

/// Play/pause and next, as their own hit targets.
///
/// `Equatable` on just the two flags that change what is drawn: the closures
/// are recreated on every rebuild of the parent and would otherwise defeat
/// SwiftUI's own equality check, redrawing the buttons on every snapshot tick.
private struct MiniPlayerTransportControls: View, Equatable {
    let isPlaying: Bool
    let isRadioMode: Bool
    let showsNext: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPlaying == rhs.isPlaying
            && lhs.isRadioMode == rhs.isRadioMode
            && lhs.showsNext == rhs.showsNext
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                AudioPlayerManager.shared.togglePlayPause()
            } label: {
                Image(systemName: playPauseSymbol)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .commit))
            .accessibilityLabel(playPauseAccessibilityLabel)
            .accessibilityHint(
                isRadioMode ? "Controls the live radio stream." : "Controls the current song."
            )

            // Radio has nothing to skip to, and the minimized bar has no room.
            if showsNext, !isRadioMode {
                Button {
                    AudioPlayerManager.shared.playNextOrRandom()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.86, dim: 0.65, haptic: .selection))
                .accessibilityLabel("Next track")
                .accessibilityHint("Skips to the next song.")
            }
        }
    }

    private var playPauseAccessibilityLabel: String {
        if isRadioMode {
            return isPlaying ? "Stop live radio" : "Play live radio"
        }
        return isPlaying ? "Pause" : "Play"
    }

    private var playPauseSymbol: String {
        if isRadioMode {
            return isPlaying ? "stop.fill" : "play.fill"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }
}
