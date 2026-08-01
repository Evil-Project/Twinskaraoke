import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject var audioManager = AudioManager.shared
    var body: some View {
        HomeView()
            .environmentObject(audioManager)
    }
}

#Preview {
    ContentView()
}

enum WatchHaptic {
    enum Feedback {
        case click
        case start
        case stop
        case success
        case failure
        case next
        case previous
    }

    static func play(_ feedback: Feedback = .click) {
        let type: WKHapticType = switch feedback {
        case .click:
            .click
        case .start:
            .start
        case .stop:
            .stop
        case .success:
            .success
        case .failure:
            .failure
        case .next:
            .directionUp
        case .previous:
            .directionDown
        }
        WKInterfaceDevice.current().play(type)
    }
}

struct WatchSongArtwork: View {
    let url: URL?
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 6
    var isCurrent = false
    var isPlaying = false

    var body: some View {
        ZStack {
            WatchCachedImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.16))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.34, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if isCurrent {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appAccent, lineWidth: 2)
                    .frame(width: size, height: size)
            }

            if isCurrent {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        WatchNowPlayingGlyph(isPlaying: isPlaying)
                            .padding(3)
                            .background(Color.black.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(3)
                .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }
}

struct WatchNowPlayingGlyph: View {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var animated = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(Color.appAccent)
                    .frame(width: 2, height: barHeight(for: index))
                    .scaleEffect(y: barScale(for: index), anchor: .bottom)
                    .opacity(isPlaying ? 1 : 0.68)
                    .animation(barAnimation(for: index), value: animated)
            }
        }
        .frame(width: 12, height: 12)
        .onAppear(perform: syncAnimation)
        .compatibleOnChange(of: isPlaying) { _ in
            syncAnimation()
        }
        .compatibleOnChange(of: reduceMotion) { _ in
            syncAnimation()
        }
    }

    private func syncAnimation() {
        animated = isPlaying && !reduceMotion
    }

    private func barHeight(for index: Int) -> CGFloat {
        [9, 12, 7][index]
    }

    private func barScale(for index: Int) -> CGFloat {
        guard isPlaying && !reduceMotion else { return 0.46 }
        let activeScales: [CGFloat] = [0.95, 0.42, 0.78]
        let restingScales: [CGFloat] = [0.38, 0.9, 0.34]
        return animated ? activeScales[index] : restingScales[index]
    }

    private func barAnimation(for index: Int) -> Animation? {
        guard isPlaying, !reduceMotion else {
            return reduceMotion ? nil : .easeOut(duration: 0.14)
        }
        let durations = [0.46, 0.58, 0.5]
        return .easeInOut(duration: durations[index])
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.06)
    }
}

struct WatchSongRow: View {
    let song: Song
    var isCurrent = false
    var isPlaying = false
    var showsDuration = false
    var trailingSystemImage: String?
    var artworkSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 10) {
            WatchSongArtwork(
                url: song.rowImageURL,
                size: artworkSize,
                isCurrent: isCurrent,
                isPlaying: isPlaying
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isCurrent ? .appAccent : .primary)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCurrent ? .appAccent : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            } else if showsDuration {
                Text(song.durationText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, isCurrent ? 4 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent.opacity(0.08))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var accessibilityValue: String {
        var parts = [song.artistName]
        if isCurrent {
            parts.append(isPlaying ? "Playing" : "Paused")
        } else if showsDuration, !song.durationText.isEmpty {
            parts.append(song.durationText)
        }
        return parts.joined(separator: ", ")
    }
}

struct WatchEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

/// Shown when an initial load fails, so a network error is not mistaken for
/// an empty library. Mirrors WatchEmptyState with an added retry action.
struct WatchLoadErrorState: View {
    let title: String
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retryAction)
                .buttonStyle(.watchPressable)
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}
