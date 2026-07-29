import SwiftUI

// MARK: - Artwork

/// Rounded song / playlist artwork with a graceful music-note placeholder.
struct TVArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 12

    var body: some View {
        // `scaledToFill` reports the *image's* scaled size rather than the size
        // it was proposed, so on its own the overflow escapes the layout bounds
        // and the clip crops nothing: a landscape cover bleeds sideways over
        // whatever sits beside it, while a square one looks fine. Overlaying
        // onto a flexible `Color.clear` pins the layout size to the frame the
        // caller set, so the clip has real bounds to crop against.
        Color.clear
            .overlay {
                TVRemoteImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    MusicArtworkPlaceholder(cornerRadius: cornerRadius)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct MusicArtworkPlaceholder: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Now Playing glyph

/// Animated bars shown over the artwork of the currently playing item.
struct TVNowPlayingGlyph: View {
    var isPlaying: Bool
    @State private var animated = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.appAccent)
                    .frame(width: 4, height: 18)
                    .scaleEffect(y: barScale(for: index), anchor: .bottom)
                    .animation(barAnimation(for: index), value: animated)
            }
        }
        .frame(width: 22, height: 18)
        .onAppear { animated = isPlaying }
        .onChange(of: isPlaying) { _, newValue in animated = newValue }
    }

    private func barScale(for index: Int) -> CGFloat {
        guard isPlaying else { return 0.4 }
        let active: [CGFloat] = [0.95, 0.45, 0.8]
        let resting: [CGFloat] = [0.4, 0.9, 0.35]
        return animated ? active[index] : resting[index]
    }

    private func barAnimation(for index: Int) -> Animation? {
        guard isPlaying else { return .easeOut(duration: 0.2) }
        let durations = [0.5, 0.62, 0.54]
        return .easeInOut(duration: durations[index])
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.08)
    }
}

// MARK: - Song card (shelves)

/// A focusable poster-style card used inside horizontal shelves.
struct TVSongCard: View {
    let song: Song
    var isCurrent = false
    var isPlaying = false
    let action: () -> Void

    private let width: CGFloat = 240

    var body: some View {
        // Spacing has to clear the `.card` focus lift, or a focused poster
        // grows down into its own caption.
        VStack(alignment: .leading, spacing: 30) {
            Button(action: action) {
                ZStack(alignment: .bottomTrailing) {
                    TVArtwork(url: song.imageURL)
                        .frame(width: width, height: width)
                    if isCurrent {
                        TVNowPlayingGlyph(isPlaying: isPlaying)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(10)
                    }
                }
            }
            .buttonStyle(.card)

            TVPosterCaption(
                title: song.title,
                subtitle: song.artistName,
                titleTint: isCurrent ? .appAccent : .primary,
                width: width
            )
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title)
        .accessibilityValue(song.artistName)
    }
}

// MARK: - Poster caption

/// Title + subtitle shown beneath a focusable poster. Kept outside the `.card`
/// button so it doesn't scale with the focus lift or crowd the highlight's
/// rounded edge, and inset slightly from the poster's width.
struct TVPosterCaption: View {
    let title: String
    let subtitle: String
    var titleTint: Color = .primary
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(titleTint)
                .lineLimit(1)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Song row (lists)

/// Full-width list row. Deliberately *not* `.buttonStyle(.card)`: the card
/// style is sized for poster content, and on a row this wide its focus lift
/// grows the row laterally and raises it above neighbouring content, so a
/// focused row spills over whatever sits above the list. Rows instead take the
/// flat inset-highlight treatment, which stays inside its own bounds.
struct TVSongRow: View {
    let index: Int?
    let song: Song
    var isCurrent = false
    var isPlaying = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                if let index {
                    // `fixedSize` rather than a fixed `width`: two monospaced
                    // digits at tvOS `.title3` are wider than the 44pt this
                    // used to be, so track 10 onwards wrapped to a second line
                    // and stacked its digits. Taking the text's ideal width
                    // means three-digit tracks can't reintroduce that, while
                    // `minWidth` keeps the column aligned for single digits.
                    Text("\(index)")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Self.subduedText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 64, alignment: .trailing)
                }

                ZStack {
                    TVArtwork(url: song.rowImageURL, cornerRadius: 8)
                        .frame(width: 72, height: 72)
                    if isCurrent {
                        TVNowPlayingGlyph(isPlaying: isPlaying)
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.headline)
                        .foregroundStyle(isCurrent ? Color.appAccent : .primary)
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.subheadline)
                        .foregroundStyle(Self.subduedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if !song.durationText.isEmpty {
                    Text(song.durationText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Self.subduedText)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        // `.plain` draws tvOS's own focus pill, which stays within the row's
        // own bounds — no background of our own is needed here.
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel(song.title)
        .accessibilityValue("\(song.artistName), \(song.durationText)")
    }

    /// Explicitly derived from `.primary` rather than using `.secondary`: on
    /// tvOS a plain button propagates its tint into secondary labels, which
    /// turned every artist name and duration accent-red. Deriving from
    /// `.primary` keeps them neutral and still flips to dark text inside the
    /// focus pill.
    private static let subduedText = Color.primary.opacity(0.6)
}

// MARK: - Text button

/// Low-emphasis text button that still shows where the remote is pointing.
///
/// `.buttonStyle(.borderless)` leaves a bare text label with no usable focus
/// treatment on tvOS, so these read as unfocusable. `.plain` draws the system
/// focus pill — the same one `TVSongRow` relies on — and the padding is what
/// gives that pill a target-sized shape to fill instead of hugging the glyphs.
struct TVTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.vertical, 14)
                .padding(.horizontal, 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action button

/// Icon + title action button for page-level actions.
///
/// The tvOS default button style inherits the app's accent tint, which rendered
/// these as red fill under a red label — the focused button's text disappeared
/// into its own background, and a `.destructive` role washed out to pink on
/// pink. `.plain` gives the standard focus pill instead, and the label colour is
/// driven off focus explicitly so it stays legible in both states rather than
/// depending on what the style decides to do with the inherited tint.
struct TVActionButton: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .foregroundStyle(labelColor)
                .padding(.vertical, 16)
                .padding(.horizontal, 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var labelColor: Color {
        // The focus pill is white, so the label has to invert with it.
        if isFocused { return .black }
        return isDestructive ? .appAccent : .primary
    }
}

// MARK: - Section header

struct TVSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - States

struct TVEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TVLoadErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Something went wrong")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
