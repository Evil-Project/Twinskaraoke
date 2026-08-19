import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The active queue mode, drawn as a small glyph on the corner of the Playing
/// Next button the way Apple Music does. Autoplay is deliberately absent: it is
/// on by default, so badging it would mean a permanent glyph that says nothing —
/// Apple Music leaves it out for the same reason. Only one glyph fits, so
/// repeat outranks shuffle: repeat changes where the queue ends, which is the
/// less obvious of the two once playback is under way.
enum PlayerQueueModeBadge {
    case shuffle, repeatAll, repeatOne

    var symbol: String {
        switch self {
        case .shuffle: "shuffle"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        }
    }

    var label: String {
        switch self {
        case .shuffle: "Shuffle on"
        case .repeatAll: "Repeat all"
        case .repeatOne: "Repeat one"
        }
    }

    static func resolve(isShuffled: Bool, repeatMode: RepeatMode) -> PlayerQueueModeBadge? {
        switch repeatMode {
        case .one: return .repeatOne
        case .all: return .repeatAll
        case .off: return isShuffled ? .shuffle : nil
        }
    }
}

struct PlayerBottomToolbar: View {
    @Environment(AudioPlayerManager.self) var audioManager
    @Environment(\.appReduceMotion) private var reduceMotion
    @Binding var showingQueue: Bool
    let song: Song
    let onLyricsToggle: () -> Void
    let showLyrics: Bool
    var horizontalPadding: CGFloat = 48

    /// Radio has no queue to shuffle or repeat, so the badge stays off there.
    private var queueModeBadge: PlayerQueueModeBadge? {
        guard !audioManager.isRadioMode else { return nil }
        return PlayerQueueModeBadge.resolve(
            isShuffled: audioManager.isShuffled,
            repeatMode: audioManager.repeatMode
        )
    }

    private var badgeAnimation: Animation? {
        reduceMotion ? nil : AppMotion.snap
    }

    private var badgeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6))
    }

    var body: some View {
        HStack(spacing: audioManager.isRadioMode ? 56 : 0) {
            if !audioManager.isRadioMode {
                Button {
                    onLyricsToggle()
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(showLyrics ? .primary : .secondary)
                        .frame(width: 44, height: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55, haptic: .selection))
                .accessibilityLabel(showLyrics ? "Hide Lyrics" : "Show Lyrics")
                .accessibilityValue(showLyrics ? "On" : "Off")
            }
            #if canImport(UIKit)
                ZStack {
                    Image(systemName: routeSymbolName(audioManager.routeIcon))
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    AirPlayRoutePickerView()
                        .frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)
                .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AirPlay")
                .accessibilityHint("Choose an audio output")
            #endif
            Button {
                AppHaptic.selection.play()
                showingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    // Cornered on the button's frame rather than on the glyph:
                    // the badge clears the list icon's top rule that way, so
                    // the two never overlap at any Dynamic Type size.
                    .overlay(alignment: .topTrailing) { queueModeBadgeView }
                    .frame(maxWidth: audioManager.isRadioMode ? nil : .infinity)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.85, dim: 0.55))
            .accessibilityLabel("Playing Next")
            .accessibilityValue(queueModeBadge?.label ?? "")
            .accessibilityHint("Show the queue for \(song.title)")
            .accessibilityIdentifier("PlayerToolbar.PlayingNext")
            .animation(badgeAnimation, value: queueModeBadge?.symbol)
        }
        .padding(.horizontal, audioManager.isRadioMode ? 0 : horizontalPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var queueModeBadgeView: some View {
        if let badge = queueModeBadge {
            Group {
                if reduceMotion {
                    Image(systemName: badge.symbol)
                } else {
                    Image(systemName: badge.symbol)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16)
            .background(Color.appPlayerActionFill, in: Circle())
            .offset(x: 2, y: -2)
            .transition(badgeTransition)
            .accessibilityHidden(true)
        }
    }

    private func routeSymbolName(_ name: String) -> String {
        #if canImport(UIKit)
            if UIImage(systemName: name) != nil { return name }
        #endif
        return "airplayaudio"
    }
}
