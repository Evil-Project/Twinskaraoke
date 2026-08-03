import SwiftUI

/// Full-screen form for creating a playlist from the TV.
///
/// The iOS `CreatePlaylistSheet` is a compact card built around a keyboard that
/// slides up under it; on tvOS every field is a focus target and the keyboard
/// takes over the screen, so the layout is rebuilt here rather than shared.
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
        // Scrollable as a safety net, but the layout is sized to fit the sheet
        // without scrolling: on tvOS a scroll only happens when focus moves, so
        // anything below the fold is easy to miss entirely.
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

    /// A plain `Toggle` here renders as a full-width bar filled with the app's
    /// accent tint, with its own label lost inside the fill — unreadable, and
    /// nothing like the fields above it. This is the same flat focus-pill
    /// treatment `TVSongRow` uses, so the row reads as one more control.
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
                // Stated explicitly because a plain button on tvOS otherwise
                // tints its label with the app accent — the state here would
                // read as red, and as an alert rather than a setting.
                .foregroundStyle(privacyFocused ? Color.black : Color.primary)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
                // Drawn only when unfocused so it can't paint over the focus
                // pill the plain style puts behind the label.
                .background(privacyFocused ? Color.clear : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .focused($privacyFocused)
            .disabled(isSaving)
            .accessibilityLabel("Playlist privacy")
            .accessibilityValue(isPublic ? "Public" : "Private")
            // The label replaces the composed children, so without a hint the
            // announcement is "Playlist privacy, Private, button" — nothing
            // says that activating it switches the setting.
            .accessibilityHint("Switches between private and public.")

            Text("Public playlists can be discovered by other users.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// Cancel stays enabled and the create button stays in place while saving,
    /// rather than being disabled and swapped for a bare progress view: tvOS
    /// moves focus off a control that becomes unfocusable, and with every
    /// control in the sheet disabled the focus engine has nowhere to go — the
    /// remote goes dead until the request lands.
    private var actions: some View {
        HStack(spacing: 20) {
            TVActionButton(title: "Cancel", systemImage: "xmark") {
                dismiss()
            }

            TVActionButton(
                title: isSaving ? "Creating…" : "Create Playlist",
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
                // String(localized:) rather than a bare literal: this is stored
                // in a String and rendered through `Label(_:systemImage:)`,
                // which picks the non-localizing StringProtocol overload, so an
                // unwrapped literal would never reach the catalog.
                errorMessage = String(localized: "Couldn’t create the playlist. Try again.")
            }
        }
    }
}
