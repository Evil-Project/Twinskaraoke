import SwiftUI

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    private let manager = UserPlaylistsManager.shared

    @State private var name = ""
    @State private var playlistDescription = ""
    @State private var isPublic = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: CreatePlaylistField?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isSaving
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CreatePlaylistArtworkPreview(name: trimmedName, isPublic: isPublic)
                        .padding(.top, 8)

                    VStack(spacing: 14) {
                        CreatePlaylistTextField(
                            title: "Name",
                            prompt: "Playlist Name",
                            text: $name,
                            axis: .horizontal
                        )
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .description
                        }

                        Divider()

                        CreatePlaylistTextField(
                            title: "Description",
                            prompt: "Optional",
                            text: $playlistDescription,
                            axis: .vertical
                        )
                        .focused($focusedField, equals: .description)
                        .lineLimit(2 ... 4)
                    }
                    .padding(16)
                    .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous))

                    VStack(spacing: 12) {
                        Toggle(isOn: $isPublic) {
                            CreatePlaylistPrivacyLabel(isPublic: isPublic)
                        }
                        .tint(.appAccent)
                        .onChange(of: isPublic) { _, _ in
                            AppHaptic.selection.play()
                        }

                        Text("Public playlists can be discovered by other users.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: AM.Radius.sheet, style: .continuous))

                    if let errorMessage {
                        CreatePlaylistErrorBanner(message: errorMessage)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }

                    Button {
                        save()
                    } label: {
                        CreatePlaylistSaveLabel(isSaving: isSaving)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.8, haptic: canSave ? .commit : nil))
                    .disabled(!canSave)
                    .accessibilityLabel("Create playlist")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .smoothScrolling()
            .musicScreenBackground()
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // These carry their own glass, so the toolbar must not put its
                // shared glass behind them as well.
                ToolbarItem(placement: .cancellationAction) {
                    GlassXButton(action: {
                        AppHaptic.selection.play()
                        dismiss()
                    })
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        GlassCheckmarkButton(
                            action: { save() },
                            isEnabled: canSave
                        )
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                focusedField = .name
            }
            .animation(reduceMotion ? nil : AppMotion.quick, value: isSaving)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: errorMessage)
            .animation(reduceMotion ? nil : AppMotion.quick, value: trimmedName)
        }
    }

    private func save() {
        guard canSave else {
            AppHaptic.warning.play()
            return
        }

        isSaving = true
        errorMessage = nil
        focusedField = nil

        manager.createPlaylist(
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            isPublic: isPublic
        ) { success in
            isSaving = false
            if success {
                AppHaptic.success.play()
                dismiss()
            } else {
                AppHaptic.error.play()
                errorMessage = "Failed to create playlist. Please try again."
            }
        }
    }
}

private enum CreatePlaylistField: Hashable {
    case name
    case description
}

private struct CreatePlaylistArtworkPreview: View {
    let name: String
    let isPublic: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(name.isEmpty ? "New Playlist" : name)
                .scaledSystemFont(size: 28, weight: .bold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Label(isPublic ? "Public Playlist" : "Private Playlist", systemImage: isPublic ? "person.2.fill" : "lock.fill")
                .scaledSystemFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name.isEmpty ? "New private playlist" : "\(name), \(isPublic ? "public" : "private") playlist")
    }
}

private struct CreatePlaylistTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .scaledSystemFont(size: 12, weight: .bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField(prompt, text: $text, axis: axis)
                .scaledSystemFont(size: 17)
                .textInputAutocapitalization(.words)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreatePlaylistPrivacyLabel: View {
    let isPublic: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPublic ? "person.2.fill" : "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isPublic ? .white : Color.appAccent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isPublic ? Color.appAccent : Color.appAccent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(isPublic ? "Public" : "Private")
                    .scaledSystemFont(size: 16, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(isPublic ? "Visible to other listeners" : "Only you can edit this playlist")
                    .scaledSystemFont(size: 13)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CreatePlaylistErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .scaledSystemFont(size: 14, weight: .medium)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.appAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CreatePlaylistSaveLabel: View {
    let isSaving: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(.appControlActiveForeground)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
            }
            Text(isSaving ? "Creating..." : "Create Playlist")
                .scaledSystemFont(size: 17, weight: .semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .foregroundStyle(Color.appControlActiveForeground)
        .background(Color.appControlActiveFill, in: Capsule())
        .opacity(isSaving ? 0.72 : 1)
    }
}
