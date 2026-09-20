import SwiftUI
struct TVCreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let manager = TVUserPlaylistsManager.shared

    @State private var name = ""
    @State private var playlistDescription = ""
    @State private var isPublic = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @FocusState private var privacyFocused: Bool

    private enum Field: Hashable {
        case name
        case description
    }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                fields
                privacyRow

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(Color.appAccent)
                }

                actions
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
            .padding(.vertical, 44)
        }
        .onAppear { focusedField = .name }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Playlist")
                .font(.system(size: 44, weight: .bold))
            Text("Add songs to it from any of your devices.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Playlist Name", text: $name)
                .focused($focusedField, equals: .name)
                .disabled(isSaving)

            TextField("Description (optional)", text: $playlistDescription)
                .focused($focusedField, equals: .description)
                .disabled(isSaving)
        }
    }
    private var privacyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isPublic.toggle()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: isPublic ? "person.2.fill" : "lock.fill")
                    Text(isPublic ? "Public" : "Private")
                    Spacer(minLength: 12)
                    Text(isPublic ? "Anyone can find it" : "Only you can see it")
                        .foregroundStyle(privacyFocused ? Color.black.opacity(0.6) : Color.primary.opacity(0.6))
                }
                .font(.title3)
                .foregroundStyle(privacyFocused ? Color.black : Color.primary)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
                .background(privacyFocused ? Color.clear : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .focused($privacyFocused)
            .disabled(isSaving)
            .accessibilityLabel("Playlist privacy")
            .accessibilityValue(isPublic ? "Public" : "Private")
            .accessibilityHint("Switches between private and public.")

            Text("Public playlists can be discovered by other users.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    private var actions: some View {
        HStack(spacing: 20) {
            TVActionButton(title: String(localized: "Cancel"), systemImage: "xmark") {
                dismiss()
            }

            TVActionButton(
                title: isSaving ? String(localized: "Creating…") : String(localized: "Create Playlist"),
                systemImage: "plus"
            ) {
                save()
            }
            .disabled(!canSave)

            if isSaving {
                ProgressView()
            }
        }
        .padding(.top, 8)
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        focusedField = nil

        Task {
            let created = await manager.create(
                name: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                isPublic: isPublic
            )
            isSaving = false
            if created {
                dismiss()
            } else {
                errorMessage = String(localized: "Couldn’t create the playlist. Try again.")
            }
        }
    }
}
