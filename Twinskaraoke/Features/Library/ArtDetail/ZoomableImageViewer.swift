import SwiftUI

struct ZoomableImageViewer: View {
    let url: URL?
    let lowResURL: URL?
    @Binding var saveStatus: ArtworkSaveStatus
    let onSave: () -> Void
    var title: String?
    var subtitle: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showOverlay = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                RemoteArtworkImage(
                    url: url, cornerRadius: 0, contentMode: .fit, showsLoading: true,
                    lowResURL: lowResURL, transparentBackground: true, fullResolution: true
                )
                .scaleEffect(scale)
                .offset(offset)
                .modifier(
                    PinchToZoomModifier(
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        lastOffset: $lastOffset,
                        reduceMotion: reduceMotion
                    )
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .simultaneousGesture(imageTapGesture)
            }
            if showOverlay {
                VStack {
                    HStack {
                        GlassXButton(action: {
                            AppHaptic.light.play()
                            dismiss()
                        })
                        Spacer()
                        GlassActionButton(
                            action: {
                                AppHaptic.selection.play()
                                onSave()
                            },
                            systemImage: saveIconName,
                            foregroundColor: saveIconColor,
                            isLoading: saveStatus == .saving,
                            accessibilityLabel: saveAccessibilityLabel
                        )
                        .disabled(saveStatus.isSaving)
                    }
                    .padding()
                    Spacer()
                    if visibleTitle != nil || visibleSubtitle != nil {
                        VStack(spacing: 4) {
                            if let title = visibleTitle {
                                Text(title)
                                    .scaledSystemFont(size: 17, weight: .bold)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            if let subtitle = visibleSubtitle {
                                Text(subtitle)
                                    .scaledSystemFont(size: 14)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
    }

    private var imageTapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    toggleZoom()
                case .second:
                    toggleOverlay()
                }
            }
    }

    private func toggleZoom() {
        AppHaptic.medium.play()
        let update = {
            if scale > 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2
                lastScale = 2
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.spring()) {
                update()
            }
        }
    }

    private func toggleOverlay() {
        AppHaptic.selection.play()
        if reduceMotion {
            showOverlay.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                showOverlay.toggle()
            }
        }
    }

    private var visibleTitle: String? {
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    private var visibleSubtitle: String? {
        guard let subtitle, !subtitle.isEmpty else { return nil }
        return subtitle
    }

    private var saveIconName: String {
        switch saveStatus {
        case .success: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .saving, .idle: "square.and.arrow.down"
        }
    }

    private var saveIconColor: Color {
        switch saveStatus {
        case .success: .green
        case .failed: .orange
        case .saving: .white
        case .idle: Color.appGlassForeground
        }
    }

    private var saveAccessibilityLabel: String {
        switch saveStatus {
        case .saving:
            "Saving image"
        case .success:
            "Image saved"
        case .failed:
            "Image save failed"
        case .idle:
            "Save image"
        }
    }
}
