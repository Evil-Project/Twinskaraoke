import SwiftUI

struct AccountView: View {
    @ObservedObject private var auth = WatchAuthManager.shared
    /// Watched only for `cacheRevision`: a song that finishes downloading while
    /// this screen is open changes what "Downloaded Audio" should say, and
    /// leaving it to `onAppear` meant the listener had to navigate away and
    /// back before the figure — and whether "Clear Cache" is even enabled —
    /// caught up.
    @ObservedObject private var audioManager = AudioManager.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @AppStorage(AppLanguage.storageKey) private var languageMode: String = AppLanguage.system.rawValue
    @State private var showsFullGuestID = false
    @State private var showsClearCacheConfirmation = false
    @State private var cacheSizeBytes: Int64 = 0

    /// `.file` counts the way a storage screen is expected to: what the disk
    /// gives back, not the decimal size of the payload.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private var cacheSizeText: String {
        Self.byteFormatter.string(fromByteCount: cacheSizeBytes)
    }

    private func refreshCacheSize() {
        cacheSizeBytes = AudioManager.cacheSizeBytes()
    }

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        List {
            Section {
                WatchAccountHeader(
                    username: auth.username,
                    avatarURL: auth.avatarURL,
                    linkState: auth.linkState
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if auth.linkState != .signedIn {
                Section("iPhone") {
                    WatchAccountStatusRow(
                        systemImage: "iphone",
                        tint: .blue,
                        title: auth.linkState == .awaitingPhone
                            ? "Waiting for iPhone"
                            : "Sign in on iPhone",
                        value: auth.linkState == .awaitingPhone
                            ? "Your session is ready but your iPhone is out of reach. Keep it nearby."
                            : "Sign in on your iPhone and this watch follows automatically."
                    )

                    if auth.linkState == .awaitingPhone {
                        Button {
                            auth.syncNow()
                            WatchHaptic.play(.click)
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.watchPressable)
                        .disabled(auth.isSyncing)
                        .accessibilityLabel("Try Again")
                        .accessibilityHint("Asks your iPhone for the session again.")
                    }
                }
            }

            Section("Session") {
                Button {
                    showsFullGuestID.toggle()
                    WatchHaptic.play(showsFullGuestID ? .success : .click)
                } label: {
                    WatchAccountTokenRow(
                        title: "Guest ID",
                        value: guestIDText,
                        showsFullValue: showsFullGuestID
                    )
                }
                .buttonStyle(.watchPressable)
                .accessibilityLabel("Guest ID")
                .accessibilityValue(showsFullGuestID ? GuestIdentity.current : guestIDText)
                .accessibilityHint(showsFullGuestID ? "Hides the full guest ID." : "Reveals the full guest ID.")

                WatchAccountStatusRow(
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .appAccent,
                    title: "Service",
                    value: serviceRegionText
                )
            }

            Section("Playback") {
                WatchAccountStatusRow(
                    systemImage: "applewatch",
                    tint: .blue,
                    title: "Plays On This Watch",
                    value: "Playback is independent — starting a song here does not move it to your iPhone"
                )
                WatchAccountStatusRow(
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    title: auth.linkState == .signedIn ? "Signed in" : "Guest playback",
                    value: "Ready for browsing and music"
                )
            }

            Section("Storage") {
                WatchAccountStatusRow(
                    systemImage: "internaldrive",
                    tint: .indigo,
                    title: "Downloaded Audio",
                    value: cacheSizeText
                )

                Button(role: .destructive) {
                    showsClearCacheConfirmation = true
                    WatchHaptic.play(.click)
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.watchPressable)
                .disabled(cacheSizeBytes == 0)
                .accessibilityLabel("Clear Cache")
                .accessibilityValue(cacheSizeText)
                .accessibilityHint("Deletes songs saved on this watch. They download again when played.")
            }

            Section("Language") {
                Picker("Language", selection: $languageMode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .compatibleOnChange(of: languageMode) { _ in
                    WatchHaptic.play(.click)
                }
                .accessibilityHint("Changes the language used on this watch.")
            }

            Section("Motion") {
                Toggle("Respect Reduce Motion", isOn: $respectReducedMotion)
                    .compatibleOnChange(of: respectReducedMotion) { _ in
                        WatchHaptic.play(.click)
                    }
            }
        }
        .navigationTitle("Account")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsFullGuestID)
        .onAppear(perform: refreshCacheSize)
        .compatibleOnChange(of: audioManager.cacheRevision) { _ in
            refreshCacheSize()
        }
        .confirmationDialog(
            "Clear cached audio?",
            isPresented: $showsClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                AudioManager.shared.clearCache()
                refreshCacheSize()
                WatchHaptic.play(.success)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Songs saved on this watch are deleted. They download again the next time you play them.")
        }
    }

    private var guestIDText: String {
        if showsFullGuestID {
            return GuestIdentity.current
        }
        return "\(GuestIdentity.current.prefix(8))..."
    }

    private var serviceRegionText: String {
        StorageHost.api.contains(".cn") ? "China CDN" : "Global CDN"
    }
}

private struct WatchAccountHeader: View {
    let username: String?
    let avatarURL: URL?
    let linkState: WatchAuthManager.LinkState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(0.15))
                    WatchCachedImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 31, weight: .semibold))
                            .foregroundColor(.appAccent)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            HStack(spacing: 6) {
                WatchAccountPill(systemImage: "music.note", title: "Browse")
                if linkState == .signedIn {
                    WatchAccountPill(systemImage: "iphone", title: "Synced")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayName)
        .accessibilityValue(statusText)
    }

    private var displayName: String {
        if let username, !username.isEmpty { return username }
        return "Guest Listener"
    }

    private var statusText: String {
        switch linkState {
        case .signedIn:
            "Signed in from iPhone"
        case .awaitingPhone:
            "Waiting for iPhone"
        case .signedOut:
            "Not signed in"
        }
    }
}

private struct WatchAccountPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundColor(.appAccent)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent.opacity(0.12))
            )
    }
}

private struct WatchAccountTokenRow: View {
    let title: String
    let value: String
    let showsFullValue: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: showsFullValue ? "eye.fill" : "number")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appAccent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Spacer(minLength: 4)

            Image(systemName: showsFullValue ? "eye.slash" : "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

private struct WatchAccountStatusRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
